using System.Net;
using System.Text;
using Sona.Windows.Services;

namespace Sona.Windows.Tests;

public sealed class SonaApiClientTests
{
    [Fact]
    public async Task Login_posts_expected_json_to_configured_server()
    {
        HttpRequestMessage? captured = null;
        var handler = new StubHandler(async request =>
        {
            captured = request;
            var body = await request.Content!.ReadAsStringAsync();
            Assert.Contains("\"username\":\"alice\"", body);
            Assert.Contains("\"password\":\"secret\"", body);
            return Json(HttpStatusCode.OK, """
                {"id":"1","username":"alice","role":"ADMIN","avatarPreset":null,"avatarURL":null}
                """);
        });
        using var api = new SonaApiClient(new HttpClient(handler));
        api.ConfigureServer("http://localhost:6699/");

        var user = await api.LoginAsync("alice", "secret");

        Assert.Equal("alice", user.Username);
        Assert.True(user.IsAdmin);
        Assert.Equal("http://localhost:6699/api/v1/auth/login", captured!.RequestUri!.ToString());
        Assert.Equal(HttpMethod.Post, captured.Method);
    }

    [Fact]
    public async Task GetTracks_encodes_query_and_deserializes_track_page()
    {
        HttpRequestMessage? captured = null;
        var handler = new StubHandler(request =>
        {
            captured = request;
            return Task.FromResult(Json(HttpStatusCode.OK, """
                {"items":[{"id":"t1","title":"夜曲","artist":"周杰伦","album":"十一月的萧邦","trackNumber":1,"durationMs":226000,"codec":"FLAC","fileExtension":"flac","sampleRate":44100,"bitDepth":16,"artworkURL":"/a","streamURL":"/api/v1/tracks/t1/stream","hasLyrics":true,"metadataStatus":"LOCAL","poolType":"NORMAL","audienceType":"GENERAL","genre":"流行","relatedGenres":[],"region":"CN","artists":["周杰伦"]}],"nextCursor":null}
                """));
        });
        using var api = new SonaApiClient(new HttpClient(handler));
        api.ConfigureServer("https://sona.example/base/");

        var page = await api.GetTracksAsync("周 杰伦");

        Assert.Single(page.Items);
        Assert.Equal("3:46", page.Items[0].DurationText);
        Assert.Equal("FLAC · 44.1 kHz · 16-bit", page.Items[0].QualityText);
        Assert.Contains("q=%E5%91%A8%20%E6%9D%B0%E4%BC%A6", captured!.RequestUri!.Query);
    }

    [Fact]
    public async Task Unauthorized_response_has_user_friendly_message()
    {
        var handler = new StubHandler(_ => Task.FromResult(Json(HttpStatusCode.Unauthorized, "")));
        using var api = new SonaApiClient(new HttpClient(handler));

        var error = await Assert.ThrowsAsync<SonaApiException>(() => api.LoginAsync("bad", "bad"));

        Assert.Equal(401, error.StatusCode);
        Assert.Equal("账号、密码错误或登录已失效", error.Message);
    }

    [Fact]
    public async Task Logout_posts_to_logout_endpoint()
    {
        HttpRequestMessage? captured = null;
        var handler = new StubHandler(request =>
        {
            captured = request;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NoContent));
        });
        using var api = new SonaApiClient(new HttpClient(handler));
        api.ConfigureServer("http://localhost:6699");

        await api.LogoutAsync();

        Assert.Equal(HttpMethod.Post, captured!.Method);
        Assert.Equal("http://localhost:6699/api/v1/auth/logout", captured.RequestUri!.ToString());
    }

    [Fact]
    public async Task Discovery_uses_discovery_endpoint()
    {
        HttpRequestMessage? captured = null;
        var handler = new StubHandler(request =>
        {
            captured = request;
            return Task.FromResult(Json(HttpStatusCode.OK, "[]"));
        });
        using var api = new SonaApiClient(new HttpClient(handler));

        var tracks = await api.GetDiscoveryTracksAsync();

        Assert.Empty(tracks);
        Assert.Equal(
            "http://sosee.eu.cc:6699/api/v1/tracks/discovery?limit=50&childMode=false",
            captured!.RequestUri!.ToString());
    }

    [Fact]
    public async Task Favorites_uses_personal_track_page_endpoint()
    {
        HttpRequestMessage? captured = null;
        var handler = new StubHandler(request =>
        {
            captured = request;
            return Task.FromResult(Json(HttpStatusCode.OK, "{\"items\":[],\"nextCursor\":null}"));
        });
        using var api = new SonaApiClient(new HttpClient(handler));

        var page = await api.GetFavoriteTracksAsync();

        Assert.Empty(page.Items);
        Assert.Equal(
            "http://sosee.eu.cc:6699/api/v1/me/favorites/tracks?limit=50",
            captured!.RequestUri!.ToString());
    }

    [Fact]
    public async Task Duplicate_tracks_uses_admin_library_endpoint()
    {
        HttpRequestMessage? captured = null;
        var handler = new StubHandler(request =>
        {
            captured = request;
            return Task.FromResult(Json(HttpStatusCode.OK, "[]"));
        });
        using var api = new SonaApiClient(new HttpClient(handler));

        var groups = await api.GetDuplicateTracksAsync();

        Assert.Empty(groups);
        Assert.Equal(
            "http://sosee.eu.cc:6699/api/v1/library/tracks/duplicates",
            captured!.RequestUri!.ToString());
    }

    [Fact]
    public async Task Managed_track_delete_uses_permanent_delete_endpoint()
    {
        HttpRequestMessage? captured = null;
        var handler = new StubHandler(request =>
        {
            captured = request;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NoContent));
        });
        using var api = new SonaApiClient(new HttpClient(handler));

        await api.DeleteManagedTrackAsync("track-id");

        Assert.Equal(HttpMethod.Delete, captured!.Method);
        Assert.Equal(
            "http://sosee.eu.cc:6699/api/v1/library/tracks/track-id",
            captured.RequestUri!.ToString());
    }

    [Fact]
    public async Task Duplicate_replacement_posts_source_and_target()
    {
        HttpRequestMessage? captured = null;
        string? body = null;
        var handler = new StubHandler(async request =>
        {
            captured = request;
            body = await request.Content!.ReadAsStringAsync();
            return new HttpResponseMessage(HttpStatusCode.NoContent);
        });
        using var api = new SonaApiClient(new HttpClient(handler));

        await api.ReplaceDuplicateTrackAsync("old-track", "new-track");

        Assert.Equal(HttpMethod.Post, captured!.Method);
        Assert.Equal(
            "http://sosee.eu.cc:6699/api/v1/library/tracks/duplicates/old-track/replace",
            captured.RequestUri!.ToString());
        Assert.Contains("\"replacementTrackId\":\"new-track\"", body);
    }

    private static HttpResponseMessage Json(HttpStatusCode status, string json) => new(status)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json")
    };

    private sealed class StubHandler(Func<HttpRequestMessage, Task<HttpResponseMessage>> response) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => response(request);
    }
}
