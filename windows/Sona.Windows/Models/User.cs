namespace Sona.Windows.Models;

public sealed record User(
    string Id,
    string Username,
    string Role,
    string? AvatarPreset,
    string? AvatarURL)
{
    public bool IsAdmin => string.Equals(Role, "ADMIN", StringComparison.OrdinalIgnoreCase);
    public string RoleTitle => IsAdmin ? "管理员" : "普通用户";
}
