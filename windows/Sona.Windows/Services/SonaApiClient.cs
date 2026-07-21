using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Sona.Windows.Models;

namespace Sona.Windows.Services;

public sealed class SonaApiClient : IDisposable
{
    public const string DefaultServerURL = "http://sosee.eu.cc:6699";

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _httpClient;
    private readonly bool _ownsClient;
    private Uri _serverUri = NormalizeServerUri(DefaultServerURL);

    public SonaApiClient()
    {
        var handler = new HttpClientHandler
        {
            CookieContainer = new CookieContainer(),
            UseCookies = true
        };
        _httpClient = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };
        _ownsClient = true;
    }

    public SonaApiClient(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    public Uri ServerUri => _serverUri;

    public void ConfigureServer(string serverURL) => _serverUri = NormalizeServerUri(serverURL);

    public async Task<User> LoginAsync(string username, string password, CancellationToken cancellationToken = default)
    {
        using var response = await _httpClient.PostAsJsonAsync(
            BuildUri("/api/v1/auth/login"),
            new { username, password },
            JsonOptions,
            cancellationToken);
        return await ReadAsync<User>(response, cancellationToken);
    }

    public async Task<TrackPage> GetTracksAsync(string query = "", CancellationToken cancellationToken = default)
    {
        var path = "/api/v1/tracks?limit=50&childMode=false&sort=TITLE";
        if (!string.IsNullOrWhiteSpace(query))
        {
            path += "&q=" + Uri.EscapeDataString(query.Trim());
        }

        using var response = await _httpClient.GetAsync(BuildUri(path), cancellationToken);
        return await ReadAsync<TrackPage>(response, cancellationToken);
    }

    public async Task<IReadOnlyList<Track>> GetDiscoveryTracksAsync(
        CancellationToken cancellationToken = default)
    {
        using var response = await _httpClient.GetAsync(
            BuildUri("/api/v1/tracks/discovery?limit=50&childMode=false"),
            cancellationToken);
        return await ReadAsync<IReadOnlyList<Track>>(response, cancellationToken);
    }

    public async Task<TrackPage> GetFavoriteTracksAsync(
        CancellationToken cancellationToken = default)
    {
        using var response = await _httpClient.GetAsync(
            BuildUri("/api/v1/me/favorites/tracks?limit=50"),
            cancellationToken);
        return await ReadAsync<TrackPage>(response, cancellationToken);
    }

    public async Task LogoutAsync(CancellationToken cancellationToken = default)
    {
        using var response = await _httpClient.PostAsync(
            BuildUri("/api/v1/auth/logout"),
            content: null,
            cancellationToken);
        if (!response.IsSuccessStatusCode && response.StatusCode != HttpStatusCode.Unauthorized)
        {
            await ThrowApiErrorAsync(response, cancellationToken);
        }
    }

    public Uri ResolveUri(string pathOrURL)
    {
        if (Uri.TryCreate(pathOrURL, UriKind.Absolute, out var absolute))
        {
            return absolute;
        }

        return BuildUri(pathOrURL);
    }

    public async Task<HttpResponseMessage> OpenAudioStreamAsync(
        Track track,
        CancellationToken cancellationToken = default)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, ResolveUri(track.StreamURL));
        var response = await _httpClient.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);

        if (response.IsSuccessStatusCode)
        {
            return response;
        }

        await ThrowApiErrorAsync(response, cancellationToken);
        throw new InvalidOperationException("Unreachable");
    }

    public void Dispose()
    {
        if (_ownsClient)
        {
            _httpClient.Dispose();
        }
    }

    private Uri BuildUri(string path)
    {
        var relative = path.TrimStart('/');
        return new Uri(_serverUri, relative);
    }

    private static Uri NormalizeServerUri(string serverURL)
    {
        var value = serverURL.Trim().TrimEnd('/');
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            throw new ArgumentException("请输入有效的 HTTP 或 HTTPS 服务器地址", nameof(serverURL));
        }

        return new Uri(uri.AbsoluteUri.TrimEnd('/') + "/");
    }

    private static async Task<T> ReadAsync<T>(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        if (!response.IsSuccessStatusCode)
        {
            await ThrowApiErrorAsync(response, cancellationToken);
        }

        var result = await response.Content.ReadFromJsonAsync<T>(JsonOptions, cancellationToken);
        return result ?? throw new SonaApiException((int)response.StatusCode, "服务器响应为空");
    }

    private static async Task ThrowApiErrorAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        var detail = await response.Content.ReadAsStringAsync(cancellationToken);
        var message = response.StatusCode switch
        {
            HttpStatusCode.Unauthorized => "账号、密码错误或登录已失效",
            HttpStatusCode.Forbidden => "当前账号没有执行此操作的权限",
            _ when !string.IsNullOrWhiteSpace(detail) => $"服务器错误 {(int)response.StatusCode}：{detail}",
            _ => $"服务器错误 {(int)response.StatusCode}"
        };
        throw new SonaApiException((int)response.StatusCode, message);
    }
}
