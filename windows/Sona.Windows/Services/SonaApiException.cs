namespace Sona.Windows.Services;

public sealed class SonaApiException(int statusCode, string message) : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}
