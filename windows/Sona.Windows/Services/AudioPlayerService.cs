using LibVLCSharp.Shared;
using Sona.Windows.Models;

namespace Sona.Windows.Services;

public sealed class AudioPlayerService : IDisposable
{
    private readonly LibVLC? _libVLC;
    private readonly MediaPlayer? _mediaPlayer;
    private HttpResponseMessage? _response;
    private Stream? _stream;
    private Media? _media;

    public event EventHandler? PlaybackEnded;
    public event EventHandler? PlaybackFailed;

    public AudioPlayerService()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        Core.Initialize();
        _libVLC = new LibVLC("--no-video", "--quiet");
        _mediaPlayer = new MediaPlayer(_libVLC);
        _mediaPlayer.EndReached += (_, _) => PlaybackEnded?.Invoke(this, EventArgs.Empty);
        _mediaPlayer.EncounteredError += (_, _) => PlaybackFailed?.Invoke(this, EventArgs.Empty);
    }

    public bool IsPlaying => _mediaPlayer?.IsPlaying == true;

    public async Task PlayAsync(
        Track track,
        SonaApiClient api,
        CancellationToken cancellationToken = default)
    {
        if (_mediaPlayer is null || _libVLC is null)
        {
            throw new PlatformNotSupportedException("音频播放需要在 Windows 10/11 上验证");
        }

        DisposeCurrentMedia();
        _response = await api.OpenAudioStreamAsync(track, cancellationToken);
        _stream = await _response.Content.ReadAsStreamAsync(cancellationToken);
        _media = new Media(_libVLC, new StreamMediaInput(_stream));
        if (!_mediaPlayer.Play(_media))
        {
            throw new InvalidOperationException("播放器无法打开当前音频流");
        }
    }

    public void TogglePause()
    {
        if (_mediaPlayer is null)
        {
            return;
        }

        if (_mediaPlayer.IsPlaying)
        {
            _mediaPlayer.Pause();
        }
        else
        {
            _mediaPlayer.Play();
        }
    }

    public void Stop() => DisposeCurrentMedia();

    public void Dispose()
    {
        DisposeCurrentMedia();
        _mediaPlayer?.Dispose();
        _libVLC?.Dispose();
    }

    private void DisposeCurrentMedia()
    {
        _mediaPlayer?.Stop();
        _media?.Dispose();
        _stream?.Dispose();
        _response?.Dispose();
        _media = null;
        _stream = null;
        _response = null;
    }
}
