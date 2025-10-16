using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.EntityFrameworkCore;
using sensore_health_trial_1.Data;
using sensore_health_trial_1.Models;
using BCrypt.Net;

namespace sensore_health_trial_1.Services;

public class AuthenticationService
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly ApplicationDbContext _dbContext;

    public AuthenticationService(IHttpContextAccessor httpContextAccessor, ApplicationDbContext dbContext)
    {
        _httpContextAccessor = httpContextAccessor;
        _dbContext = dbContext;
    }

    public async Task<(bool Success, string ErrorMessage)> SignUpAsync(string email, string password, string accountType)
    {
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password) || string.IsNullOrWhiteSpace(accountType))
        {
            return (false, "All fields are required");
        }

        if (!IsValidEmail(email))
        {
            return (false, "Invalid email format");
        }

        if (password.Length < 6)
        {
            return (false, "Password must be at least 6 characters");
        }

        // Check if user already exists
        var existingUser = await _dbContext.Users
            .FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLower());

        if (existingUser != null)
        {
            return (false, "An account with this email already exists");
        }

        // Generate username from email
        var username = email.Split('@')[0].ToLower();
        var baseUsername = username;
        var counter = 1;

        // Ensure username is unique
        while (await _dbContext.Users.AnyAsync(u => u.Username == username))
        {
            username = $"{baseUsername}{counter}";
            counter++;
        }

        // Extract first and last name from email (or use defaults)
        var nameParts = email.Split('@')[0].Split('.');
        var firstName = nameParts.Length > 0 ? CapitalizeFirstLetter(nameParts[0]) : "User";
        var lastName = nameParts.Length > 1 ? CapitalizeFirstLetter(nameParts[1]) : "Account";

        var user = new User
        {
            Username = username,
            Email = email.ToLower(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(password),
            UserType = accountType.ToLower(),
            FirstName = firstName,
            LastName = lastName,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        _dbContext.Users.Add(user);
        await _dbContext.SaveChangesAsync();

        return (true, string.Empty);
    }

    public async Task<(bool Success, string ErrorMessage)> SignInAsync(string email, string password, string accountType)
    {
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password) || string.IsNullOrWhiteSpace(accountType))
        {
            return (false, "All fields are required");
        }

        // Find user by email
        var user = await _dbContext.Users
            .FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLower());

        if (user == null)
        {
            return (false, "Invalid email or password");
        }

        if (!user.IsActive)
        {
            return (false, "This account has been deactivated");
        }

        if (user.UserType.ToLower() != accountType.ToLower())
        {
            return (false, "Invalid account type selected");
        }

        // Verify password using BCrypt
        if (!BCrypt.Net.BCrypt.Verify(password, user.PasswordHash))
        {
            return (false, "Invalid email or password");
        }

        // Update last login
        user.UpdatedAt = DateTime.UtcNow;
        await _dbContext.SaveChangesAsync();

        // Create authentication cookie
        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.NameIdentifier, user.UserId.ToString()),
            new Claim(ClaimTypes.Name, user.Username),
            new Claim(ClaimTypes.Email, user.Email),
            new Claim(ClaimTypes.Role, user.UserType),
            new Claim("AccountType", user.UserType),
            new Claim("FirstName", user.FirstName),
            new Claim("LastName", user.LastName)
        };

        var claimsIdentity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
        var claimsPrincipal = new ClaimsPrincipal(claimsIdentity);

        var authProperties = new AuthenticationProperties
        {
            IsPersistent = true,
            ExpiresUtc = DateTimeOffset.UtcNow.AddHours(8),
            AllowRefresh = true
        };

        var httpContext = _httpContextAccessor.HttpContext;
        if (httpContext != null)
        {
            await httpContext.SignInAsync(
                CookieAuthenticationDefaults.AuthenticationScheme,
                claimsPrincipal,
                authProperties);
        }

        return (true, string.Empty);
    }

    public async Task SignOutAsync()
    {
        var httpContext = _httpContextAccessor.HttpContext;
        if (httpContext != null)
        {
            await httpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
        }
    }

    public bool IsAuthenticated()
    {
        var httpContext = _httpContextAccessor.HttpContext;
        return httpContext?.User?.Identity?.IsAuthenticated ?? false;
    }

    public string? GetCurrentUserEmail()
    {
        var httpContext = _httpContextAccessor.HttpContext;
        return httpContext?.User?.FindFirst(ClaimTypes.Email)?.Value;
    }

    public string? GetCurrentUserAccountType()
    {
        var httpContext = _httpContextAccessor.HttpContext;
        return httpContext?.User?.FindFirst("AccountType")?.Value;
    }

    private static string CapitalizeFirstLetter(string input)
    {
        if (string.IsNullOrEmpty(input))
            return input;

        return char.ToUpper(input[0]) + input.Substring(1).ToLower();
    }

    private static bool IsValidEmail(string email)
    {
        try
        {
            var addr = new System.Net.Mail.MailAddress(email);
            return addr.Address == email;
        }
        catch
        {
            return false;
        }
    }
}
