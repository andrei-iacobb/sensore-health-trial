using Microsoft.AspNetCore.Mvc;
using sensore_health_trial_1.Services;

namespace sensore_health_trial_1.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly AuthenticationService _authService;

    public AuthController(AuthenticationService authService)
    {
        _authService = authService;
    }

    [HttpPost("signup")]
    public async Task<IActionResult> SignUp([FromBody] SignUpRequest request)
    {
        var result = await _authService.SignUpAsync(request.Email, request.Password, request.AccountType);

        if (!result.Success)
        {
            return BadRequest(new { error = result.ErrorMessage });
        }

        // Now sign in
        var signInResult = await _authService.SignInAsync(request.Email, request.Password, request.AccountType);

        if (!signInResult.Success)
        {
            return BadRequest(new { error = signInResult.ErrorMessage });
        }

        // Get redirect URL based on account type
        string redirectUrl = request.AccountType.ToLower() switch
        {
            "patient" => "/dashboard/patient",
            "clinician" => "/dashboard/clinician",
            "admin" => "/dashboard/admin",
            _ => "/"
        };

        return Ok(new { redirectUrl });
    }

    [HttpPost("signin")]
    public async Task<IActionResult> SignIn([FromBody] SignInRequest request)
    {
        var result = await _authService.SignInAsync(request.Email, request.Password, request.AccountType);

        if (!result.Success)
        {
            return BadRequest(new { error = result.ErrorMessage });
        }

        // Get redirect URL based on account type
        string redirectUrl = request.AccountType.ToLower() switch
        {
            "patient" => "/dashboard/patient",
            "clinician" => "/dashboard/clinician",
            "admin" => "/dashboard/admin",
            _ => "/"
        };

        return Ok(new { redirectUrl });
    }

    [HttpPost("signout")]
    public async Task<IActionResult> Logout()
    {
        await _authService.SignOutAsync();
        return Ok(new { redirectUrl = "/auth" });
    }
}

public record SignUpRequest(string Email, string Password, string AccountType);
public record SignInRequest(string Email, string Password, string AccountType);
