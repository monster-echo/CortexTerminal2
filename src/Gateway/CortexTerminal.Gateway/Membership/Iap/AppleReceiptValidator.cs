using System.Reflection;
using System.Security.Cryptography.X509Certificates;
using CortexTerminal.Gateway.Membership.Iap;
using Mimo.AppStoreServerLibrary;
using Mimo.AppStoreServerLibrary.Exceptions;
using Mimo.AppStoreServerLibrary.Models;

namespace CortexTerminal.Gateway.Membership;

/// <summary>
/// Apple IAP receipt validator backed by <c>Mimo.AppStoreServerLibrary</c>.
///
/// Verifies the JWS <c>signedTransactionInfo</c> cryptographically (certificate chain +
/// ES256 signature against the bundled Apple root CAs) and returns the trusted transaction
/// fields. Any verification failure is surfaced as <see cref="IapReceiptInvalidException"/>
/// so the caller (verify endpoint / webhook) can present it to the user rather than
/// silently treating the receipt as valid.
/// </summary>
public class AppleReceiptValidator : IAppleReceiptValidator
{
    private readonly IapOptions _iap;
    private readonly ILogger<AppleReceiptValidator> _logger;

    // The SignedDataVerifier holds the parsed root certs + bundle id + environment and is
    // documented as reusable; build it once per validator instance.
    private SignedDataVerifier? _verifier;
    private readonly object _verifierGate = new();

    // Root certificates are bundled as embedded DER (.cer) resources under this folder.
    private const string RootCertResourcePrefix = "CortexTerminal.Gateway.Membership.Iap.RootCertificates.";

    public AppleReceiptValidator(IapOptions iap, ILogger<AppleReceiptValidator> logger)
    {
        _iap = iap;
        _logger = logger;
    }

    public async Task<AppleVerifiedTransaction> VerifyAsync(string signedTransaction, CancellationToken ct)
    {
        var verifier = GetVerifier();
        JwsTransactionDecodedPayload payload;
        try
        {
            payload = await verifier.VerifyAndDecodeTransaction(signedTransaction);
        }
        catch (VerificationException ex)
        {
            _logger.LogWarning(ex, "Apple receipt verification failed");
            throw new IapReceiptInvalidException(ex.Message);
        }
        catch (FormatException ex)
        {
            // The underlying JWT decoder throws FormatException (e.g. IDX10400) for payloads that
            // are not valid base64url / JSON before the library can wrap them in VerificationException.
            // Both mean the receipt is malformed -> surface as IapReceiptInvalidException.
            _logger.LogWarning(ex, "Apple receipt is malformed");
            throw new IapReceiptInvalidException(ex.Message);
        }

        // ExpiresDate is 0 when the purchase has no expiry (consumables / non-consumables).
        long? expiresMs = payload.ExpiresDate > 0 ? payload.ExpiresDate : null;

        return new AppleVerifiedTransaction(
            payload.OriginalTransactionId,
            payload.ProductId,
            expiresMs,
            payload.Type
        );
    }

    private SignedDataVerifier GetVerifier()
    {
        if (_verifier is not null)
        {
            return _verifier;
        }

        lock (_verifierGate)
        {
            if (_verifier is not null)
            {
                return _verifier;
            }

            var environment = ResolveEnvironment(_iap.Apple.Environment);
            var verifier = new SignedDataVerifier(
                LoadRootCertificates(),
                enableOnlineChecks: false,
                environment: environment,
                bundleId: _iap.Apple.BundleId
            );
            _verifier = verifier;
            return verifier;
        }
    }

    private static AppStoreEnvironment ResolveEnvironment(string name)
    {
        // AppStoreEnvironment exposes only static instances; map by name and fail loudly on
        // anything unexpected rather than defaulting silently.
        if (string.Equals(name, AppStoreEnvironment.Sandbox.Name, StringComparison.OrdinalIgnoreCase))
        {
            return AppStoreEnvironment.Sandbox;
        }

        if (string.Equals(name, AppStoreEnvironment.Production.Name, StringComparison.OrdinalIgnoreCase))
        {
            return AppStoreEnvironment.Production;
        }

        if (string.Equals(name, AppStoreEnvironment.LocalTesting.Name, StringComparison.OrdinalIgnoreCase))
        {
            return AppStoreEnvironment.LocalTesting;
        }

        throw new InvalidOperationException(
            $"Unknown Apple IAP environment '{name}'. Expected 'Sandbox', 'Production' or 'LocalTesting'."
        );
    }

    /// <summary>
    /// Loads the Apple root CAs used to validate the JWS certificate chain. Virtual so tests
    /// can substitute a mock root CA that matches a known sample fixture.
    /// </summary>
    protected virtual byte[][] LoadRootCertificates()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resources = assembly
            .GetManifestResourceNames()
            .Where(n => n.StartsWith(RootCertResourcePrefix, StringComparison.Ordinal) && n.EndsWith(".cer", StringComparison.Ordinal))
            .Order()
            .ToList();

        if (resources.Count == 0)
        {
            throw new InvalidOperationException(
                $"No Apple root certificates found as embedded resources under '{RootCertResourcePrefix}'. " +
                "Add the Apple Root CA .cer files (DER) to Membership/Iap/RootCertificates/ with BuildAction=EmbeddedResource."
            );
        }

        var certificates = new byte[resources.Count][];
        for (int i = 0; i < resources.Count; i++)
        {
            using var stream = assembly.GetManifestResourceStream(resources[i]);
            using var ms = new MemoryStream();
            stream!.CopyTo(ms);
            certificates[i] = ms.ToArray();
            // Eagerly parse so a corrupt / non-DER bundle fails fast at startup, not on the first receipt.
            _ = X509CertificateLoader.LoadCertificate(certificates[i]);
        }

        return certificates;
    }
}
