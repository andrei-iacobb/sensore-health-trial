using Microsoft.EntityFrameworkCore;
using sensore_health_trial_1.Data;

namespace sensore_health_trial_1.Services;

public class DashboardService
{
    private readonly ApplicationDbContext _dbContext;

    public DashboardService(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<DashboardStats> GetDashboardStatsAsync()
    {
        var totalUsers = await _dbContext.Users.CountAsync();
        var clinicians = await _dbContext.Users
            .Where(u => u.UserType == "clinician")
            .CountAsync();
        var patients = await _dbContext.Users
            .Where(u => u.UserType == "patient")
            .CountAsync();

        return new DashboardStats
        {
            TotalUsers = totalUsers,
            Clinicians = clinicians,
            Patients = patients,
            PendingRequests = 0  // N/A for now
        };
    }
}

public class DashboardStats
{
    public int TotalUsers { get; set; }
    public int Clinicians { get; set; }
    public int Patients { get; set; }
    public int PendingRequests { get; set; }
}
