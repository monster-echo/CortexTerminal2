using System;
using System.Linq;
using System.Threading.Tasks;
using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class EnsureUserTests : IDisposable
{
    private readonly AppDbContext _db;

    public EnsureUserTests()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase($"test-{Guid.NewGuid():N}")
            .Options;
        _db = new AppDbContext(options);
    }

    public void Dispose() => _db.Dispose();

    private static string? NormalizePhone(string? phone)
    {
        if (string.IsNullOrEmpty(phone)) return null;
        var digits = new string(phone.Where(char.IsDigit).ToArray());
        return digits.Length >= 11 ? digits[^11..] : digits;
    }

    private async Task<User?> EnsureUser(string username, string? email, string? displayName,
        string authProvider, string authProviderId)
    {
        var phoneNormalized = NormalizePhone(authProviderId);

        var existingIdentity = await _db.UserIdentities.FirstOrDefaultAsync(i =>
            i.AuthProvider == authProvider && i.AuthProviderId == authProviderId);
        if (existingIdentity is not null)
        {
            var existing = await _db.Users.FirstAsync(u => u.Id == existingIdentity.UserId);
            existing.Email = email ?? existing.Email;
            existing.DisplayName = displayName ?? existing.DisplayName;
            existing.UpdatedAtUtc = DateTimeOffset.UtcNow;
            if (email is not null) existingIdentity.Email = email;
            await _db.SaveChangesAsync();
            return existing;
        }

        if (authProvider is "phone" or "huawei" && phoneNormalized is not null)
        {
            var matchedIdentity = await _db.UserIdentities.FirstOrDefaultAsync(i =>
                i.PhoneNormalized == phoneNormalized);
            if (matchedIdentity is not null)
            {
                _db.UserIdentities.Add(new UserIdentity
                {
                    UserId = matchedIdentity.UserId,
                    AuthProvider = authProvider,
                    AuthProviderId = authProviderId,
                    Email = email,
                    PhoneNormalized = phoneNormalized,
                    CreatedAtUtc = DateTimeOffset.UtcNow
                });
                var linkedUser = await _db.Users.FirstAsync(u => u.Id == matchedIdentity.UserId);
                linkedUser.DisplayName = displayName ?? linkedUser.DisplayName;
                linkedUser.UpdatedAtUtc = DateTimeOffset.UtcNow;
                await _db.SaveChangesAsync();
                return linkedUser;
            }
        }

        if (!string.IsNullOrEmpty(email))
        {
            var matchedIdentity = await _db.UserIdentities.FirstOrDefaultAsync(i => i.Email == email);
            if (matchedIdentity is not null)
            {
                _db.UserIdentities.Add(new UserIdentity
                {
                    UserId = matchedIdentity.UserId,
                    AuthProvider = authProvider,
                    AuthProviderId = authProviderId,
                    Email = email,
                    PhoneNormalized = phoneNormalized,
                    CreatedAtUtc = DateTimeOffset.UtcNow
                });
                var linkedUser = await _db.Users.FirstAsync(u => u.Id == matchedIdentity.UserId);
                linkedUser.DisplayName = displayName ?? linkedUser.DisplayName;
                linkedUser.UpdatedAtUtc = DateTimeOffset.UtcNow;
                await _db.SaveChangesAsync();
                return linkedUser;
            }
        }

        var finalUsername = username;
        if (await _db.Users.AnyAsync(u => u.Username == username))
        {
            finalUsername = $"{username}_{authProvider}";
            if (await _db.Users.AnyAsync(u => u.Username == finalUsername))
                finalUsername = $"{username}_{authProviderId}";
        }

        var userCount = await _db.Users.CountAsync();
        var role = userCount == 0 ? "admin" : "user";

        var newUser = new User
        {
            Id = Guid.NewGuid().ToString("N"),
            Username = finalUsername,
            Email = email,
            DisplayName = displayName ?? username,
            Role = role,
            Status = "active",
            AuthProvider = authProvider,
            AuthProviderId = authProviderId,
            CreatedAtUtc = DateTimeOffset.UtcNow,
            UpdatedAtUtc = DateTimeOffset.UtcNow
        };

        _db.Users.Add(newUser);
        _db.UserIdentities.Add(new UserIdentity
        {
            UserId = newUser.Id,
            AuthProvider = authProvider,
            AuthProviderId = authProviderId,
            Email = email,
            PhoneNormalized = phoneNormalized,
            CreatedAtUtc = DateTimeOffset.UtcNow
        });
        await _db.SaveChangesAsync();
        return newUser;
    }

    [Fact]
    public async Task NewUser_CreatesUserAndIdentity()
    {
        var user = await EnsureUser("phone_2627", null, "150****2627", "phone", "+8615088132627");

        user.Should().NotBeNull();
        user!.Username.Should().Be("phone_2627");
        user.AuthProvider.Should().Be("phone");

        _db.UserIdentities.Count().Should().Be(1);
        var identity = await _db.UserIdentities.FirstAsync();
        identity.AuthProvider.Should().Be("phone");
        identity.AuthProviderId.Should().Be("+8615088132627");
        identity.PhoneNormalized.Should().Be("15088132627");
    }

    [Fact]
    public async Task SameProvider_SameId_ReturnsExistingUser()
    {
        var user1 = await EnsureUser("phone_2627", null, "150****2627", "phone", "+8615088132627");
        var user2 = await EnsureUser("phone_2627", null, "150****2627", "phone", "+8615088132627");

        user2!.Id.Should().Be(user1!.Id);
        _db.Users.Count().Should().Be(1);
        _db.UserIdentities.Count().Should().Be(1);
    }

    [Fact]
    public async Task PhoneThenHuawei_LinksToSameUser()
    {
        var phoneUser = await EnsureUser("phone_2627", null, "150****2627", "phone", "+8615088132627");
        var hwUser = await EnsureUser("hw_15088132627", null, "150****2627", "huawei", "008615088132627");

        hwUser!.Id.Should().Be(phoneUser!.Id, "huawei login should link to the same user as phone");
        hwUser.Username.Should().Be("phone_2627");

        _db.Users.Count().Should().Be(1);
        _db.UserIdentities.Count().Should().Be(2, "should have both phone and huawei identities");

        var identities = await _db.UserIdentities.ToListAsync();
        identities.Should().Contain(i => i.AuthProvider == "phone" && i.AuthProviderId == "+8615088132627");
        identities.Should().Contain(i => i.AuthProvider == "huawei" && i.AuthProviderId == "008615088132627");
    }

    [Fact]
    public async Task HuaweiThenPhone_LinksToSameUser()
    {
        var hwUser = await EnsureUser("hw_15088132627", null, "150****2627", "huawei", "008615088132627");
        var phoneUser = await EnsureUser("phone_2627", null, "150****2627", "phone", "+8615088132627");

        phoneUser!.Id.Should().Be(hwUser!.Id);
        phoneUser.Username.Should().Be("hw_15088132627");

        _db.Users.Count().Should().Be(1);
        _db.UserIdentities.Count().Should().Be(2);
    }

    [Fact]
    public async Task DifferentPhone_DoesNotLink()
    {
        var user1 = await EnsureUser("phone_2627", null, "150****2627", "phone", "+8615088132627");
        var user2 = await EnsureUser("phone_1234", null, "139****1234", "phone", "+8613912341234");

        user2!.Id.Should().NotBe(user1!.Id, "different phone numbers should create separate users");
        _db.Users.Count().Should().Be(2);
    }

    [Fact]
    public async Task EmailThenGitHub_LinksToSameUser()
    {
        var googleUser = await EnsureUser("alice", "alice@example.com", "Alice", "google", "google-sub-123");
        var githubUser = await EnsureUser("alice_gh", "alice@example.com", "Alice", "github", "alice-gh");

        githubUser!.Id.Should().Be(googleUser!.Id, "same email should link to same user");
        _db.Users.Count().Should().Be(1);
        _db.UserIdentities.Count().Should().Be(2);

        var identities = await _db.UserIdentities.ToListAsync();
        identities.Should().Contain(i => i.AuthProvider == "google");
        identities.Should().Contain(i => i.AuthProvider == "github");
    }

    [Fact]
    public async Task PhoneAndEmail_DifferentProvidersNoCommonKey_NoLink()
    {
        var phoneUser = await EnsureUser("phone_2627", null, "150****2627", "phone", "+8615088132627");
        var googleUser = await EnsureUser("alice", "alice@example.com", "Alice", "google", "google-sub-999");

        googleUser!.Id.Should().NotBe(phoneUser!.Id, "no common key between phone and Google");
    }

    [Fact]
    public async Task AllProvidersLinked_AllCanLogin()
    {
        var phoneUser = await EnsureUser("phone_2627", null, "150****2627", "phone", "+8615088132627");
        var hwUser = await EnsureUser("hw_15088132627", null, "150****2627", "huawei", "008615088132627");
        var phoneAgain = await EnsureUser("phone_2627", null, "150****2627", "phone", "+8615088132627");

        phoneAgain!.Id.Should().Be(phoneUser!.Id);
        hwUser!.Id.Should().Be(phoneUser.Id);
        _db.UserIdentities.Count().Should().Be(2);
    }

    [Fact]
    public async Task FirstUser_IsAdmin()
    {
        var user = await EnsureUser("first_user", "first@test.com", "First", "github", "gh-123");
        user!.Role.Should().Be("admin");
    }

    [Fact]
    public async Task SecondUser_IsNotAdmin()
    {
        await EnsureUser("first_user", "first@test.com", "First", "github", "gh-123");
        var second = await EnsureUser("second_user", "second@test.com", "Second", "github", "gh-456");
        second!.Role.Should().Be("user");
    }
}
