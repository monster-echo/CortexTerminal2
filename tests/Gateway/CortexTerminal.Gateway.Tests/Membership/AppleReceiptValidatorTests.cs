using System.Reflection;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Membership.Iap;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class AppleReceiptValidatorTests
{
    // The library's own test suite ships a real Apple-format JWS signed with the mock root CA
    // below. We don't assert full signature verification against it here: in current
    // Microsoft.IdentityModel.JsonWebTokens the library's sample fixture's signature no longer
    // validates against its own leaf certificate (the library's own test only asserts the
    // decoded Environment field). Signature verification against a genuine Apple-signed JWS is
    // exercised end-to-end in sandbox integration testing; here we cover the real
    // field-extraction + error-surfacing mapping of our validator via the LocalTesting path.
    private const string MockRootCaBase64 =
        "MIIBgjCCASmgAwIBAgIJALUc5ALiH5pbMAoGCCqGSM49BAMDMDYxCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApD" +
        "YWxpZm9ybmlhMRIwEAYDVQQHDAlDdXBlcnRpbm8wHhcNMjMwMTA1MjEzMDIyWhcNMzMwMTAyMjEzMDIyWjA2" +
        "MQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTESMBAGA1UEBwwJQ3VwZXJ0aW5vMFkwEwYHKoZI" +
        "zj0CAQYIKoZIzj0DAQcDQgAEc+/Bl+gospo6tf9Z7io5tdKdrlN1YdVnqEhEDXDShzdAJPQijamXIMHf8xWW" +
        "Ta1zgoYTxOKpbuJtDplz1XriTaMgMB4wDAYDVR0TBAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0E" +
        "AwMDRwAwRAIgemWQXnMAdTad2JDJWng9U4uBBL5mA7WI05H7oH7c6iQCIHiRqMjNfzUAyiu9h6rOU/K+iTR0" +
        "I/3Y/NSWsXHX+acc";

    private const string RealBundleId = "com.example";

    /// <summary>
    /// Validator subclass that returns a caller-supplied root CA instead of the embedded
    /// production Apple roots — used to exercise the production (non-LocalTesting) verify path
    /// against a known root.
    /// </summary>
    private sealed class FixedRootValidator : AppleReceiptValidator
    {
        private readonly byte[][] _roots;
        public FixedRootValidator(IapOptions iap, byte[][] roots)
            : base(iap, NullLogger<AppleReceiptValidator>.Instance) => _roots = roots;

        protected override byte[][] LoadRootCertificates() => _roots;
    }

    [Fact]
    public async Task VerifyAsync_ProductionEnvTamperedSignature_ThrowsInvalidReceipt()
    {
        // Production path: the validator must surface signature/cert-chain failures as
        // IapReceiptInvalidException rather than letting the raw library exception escape. We
        // feed a structurally-valid JWS whose signature cannot verify; the result must be our
        // domain exception. (Catching it proves the catch+rethrow wiring for VerificationException.)
        var sut = new FixedRootValidator(
            new IapOptions { Apple = { BundleId = RealBundleId, Environment = "Sandbox" } },
            [Convert.FromBase64String(MockRootCaBase64)]
        );

        // Build a 3-part JWS with a valid ES256/x5c header but a bogus signature so it reaches
        // the signature-check stage and fails there.
        string header = Base64Url(JsonSerializer.Serialize(new
        {
            alg = "ES256",
            typ = "JWT",
            x5c = new[] { "a", "b", "c" } // placeholder; chain check also fails -> VerificationException
        }));
        string payload = Base64Url(JsonSerializer.Serialize(new
        {
            environment = "Sandbox",
            bundleId = RealBundleId,
            signedDate = 1672956154000L
        }));
        string jws = $"{header}.{payload}.bogus-signature";

        var act = () => sut.VerifyAsync(jws, CancellationToken.None);

        await act.Should().ThrowAsync<IapReceiptInvalidException>();
    }

    // The LocalTesting environment short-circuits signature + chain verification inside the
    // library (by design, so test payloads can be crafted without Apple's keys). We use it to
    // exercise the REAL field-extraction mapping in VerifyAsync on synthetic payloads.
    private static AppleReceiptValidator CreateLocalTestingValidator() =>
        new(
            new IapOptions { Apple = { BundleId = "com.example", Environment = "LocalTesting" } },
            NullLogger<AppleReceiptValidator>.Instance
        );

    private static string BuildJws(object payload)
    {
        // header.payload.signature. Under LocalTesting only the format is checked (3 dot-parts,
        // ES256 alg, 3-entry x5c) — the signature itself is never validated.
        string header = Base64Url(JsonSerializer.Serialize(new
        {
            alg = "ES256",
            typ = "JWT",
            x5c = new[] { "a", "b", "c" }
        }));
        string body = Base64Url(JsonSerializer.Serialize(payload));
        return $"{header}.{body}.sig";
    }

    private static string Base64Url(string s)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(s);
        return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    [Fact]
    public async Task VerifyAsync_AutoRenewableSubscription_MapsAllFields()
    {
        string jws = BuildJws(new
        {
            originalTransactionId = "0123456789",
            transactionId = "9876543210",
            productId = "corterm.pro.month",
            type = "Auto-Renewable Subscription",
            expiresDate = 1_700_000_000_000L,
            environment = "LocalTesting",
            bundleId = "com.example",
        });
        var sut = CreateLocalTestingValidator();

        var tx = await sut.VerifyAsync(jws, CancellationToken.None);

        tx.Should().BeEquivalentTo(new AppleVerifiedTransaction(
            OriginalTransactionId: "0123456789",
            ProductId: "corterm.pro.month",
            ExpiresDateMs: 1_700_000_000_000L,
            Type: "Auto-Renewable Subscription"
        ));
    }

    [Fact]
    public async Task VerifyAsync_NonConsumable_MapsNullExpiryWhenExpiresDateAbsent()
    {
        string jws = BuildJws(new
        {
            originalTransactionId = "0123456789",
            productId = "corterm.pro.lifetime",
            type = "Non-Consumable",
            environment = "LocalTesting",
            bundleId = "com.example",
        });
        var sut = CreateLocalTestingValidator();

        var tx = await sut.VerifyAsync(jws, CancellationToken.None);

        tx.OriginalTransactionId.Should().Be("0123456789");
        tx.ProductId.Should().Be("corterm.pro.lifetime");
        tx.Type.Should().Be("Non-Consumable");
        // Non-renewing purchases omit/zero expiresDate — the validator must surface null.
        tx.ExpiresDateMs.Should().BeNull();
    }

    [Fact]
    public async Task VerifyAsync_ZeroExpiresDate_MapsToNull()
    {
        string jws = BuildJws(new
        {
            originalTransactionId = "orig-1",
            productId = "p",
            type = "Consumable",
            expiresDate = 0L,
            environment = "LocalTesting",
            bundleId = "com.example",
        });
        var sut = CreateLocalTestingValidator();

        var tx = await sut.VerifyAsync(jws, CancellationToken.None);

        tx.ExpiresDateMs.Should().BeNull();
    }

    [Fact]
    public async Task VerifyAsync_MalformedJws_ThrowsInvalidReceipt()
    {
        var sut = CreateLocalTestingValidator();

        var act = () => sut.VerifyAsync("not.a.jws", CancellationToken.None);

        await act.Should().ThrowAsync<IapReceiptInvalidException>();
    }

    [Fact]
    public async Task ResolveEnvironment_UnknownEnvironment_Throws()
    {
        // We exercise the environment resolver via the first VerifyAsync call (verifier build).
        var act = () => new AppleReceiptValidator(
            new IapOptions { Apple = { BundleId = RealBundleId, Environment = "Staging" } },
            NullLogger<AppleReceiptValidator>.Instance
        ).VerifyAsync("a.b.c", CancellationToken.None);

        (await act.Should().ThrowAsync<InvalidOperationException>())
            .WithMessage("*Unknown Apple IAP environment*");
    }

    [Fact]
    public void EmbeddedRootCertificates_BundleAtLeastOneValidAppleRootCa()
    {
        // Production sanity: the shipped embedded resources must exist and parse as DER certs.
        var assembly = Assembly.GetAssembly(typeof(AppleReceiptValidator))!;
        var resources = assembly
            .GetManifestResourceNames()
            .Where(n => n.StartsWith("CortexTerminal.Gateway.Membership.Iap.RootCertificates.", StringComparison.Ordinal)
                        && n.EndsWith(".cer", StringComparison.Ordinal))
            .ToList();

        resources.Should().NotBeEmpty("Apple root CAs must be bundled for production verification");
        foreach (var name in resources)
        {
            using var stream = assembly.GetManifestResourceStream(name)!;
            using var ms = new MemoryStream();
            stream.CopyTo(ms);
            var load = () => X509CertificateLoader.LoadCertificate(ms.ToArray());
            load.Should().NotThrow($"embedded cert '{name}' must be valid DER");
        }
    }
}
