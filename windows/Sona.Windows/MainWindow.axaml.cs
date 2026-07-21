using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Threading;
using Sona.Windows.Models;
using Sona.Windows.Services;

namespace Sona.Windows;

public sealed partial class MainWindow : Window
{
    private readonly SonaApiClient _api = new();
    private readonly AudioPlayerService _player = new();
    private readonly ObservableCollection<Track> _tracks = [];
    private readonly ObservableCollection<Track> _queue = [];
    private User? _user;
    private Track? _currentTrack;
    private int _currentIndex = -1;

    public MainWindow()
    {
        InitializeComponent();
        TracksList.ItemsSource = _tracks;
        QueueList.ItemsSource = _queue;
        _player.PlaybackEnded += (_, _) => Dispatcher.UIThread.Post(() => _ = PlayNextAsync());
        _player.PlaybackFailed += (_, _) => Dispatcher.UIThread.Post(() =>
        {
            StatusLabel.Text = "播放失败：LibVLC 无法解码当前音频流";
            PlayPauseButton.Content = "▶";
        });
        Closed += (_, _) =>
        {
            _player.Dispose();
            _api.Dispose();
        };
    }

    private async void Login_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
        => await LoginAsync();

    private async void PasswordBox_KeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            await LoginAsync();
        }
    }

    private async Task LoginAsync()
    {
        if (string.IsNullOrWhiteSpace(UsernameBox.Text) || string.IsNullOrWhiteSpace(PasswordBox.Text))
        {
            ShowLoginError("请输入账号和密码");
            return;
        }

        LoginButton.IsEnabled = false;
        LoginButton.Content = "正在登录…";
        LoginError.IsVisible = false;
        try
        {
            _api.ConfigureServer(ServerBox.Text ?? string.Empty);
            _user = await _api.LoginAsync(UsernameBox.Text.Trim(), PasswordBox.Text);
            UsernameLabel.Text = _user.Username;
            RoleLabel.Text = _user.RoleTitle;
            AvatarLetter.Text = _user.Username[..1].ToUpperInvariant();
            LoginPanel.IsVisible = false;
            Shell.IsVisible = true;
            await LoadTracksAsync();
        }
        catch (Exception exception) when (exception is SonaApiException or HttpRequestException or ArgumentException or TaskCanceledException)
        {
            ShowLoginError(exception is TaskCanceledException ? "连接服务器超时" : exception.Message);
        }
        finally
        {
            LoginButton.IsEnabled = true;
            LoginButton.Content = "登录";
        }
    }

    private async Task LoadTracksAsync(string query = "")
    {
        ShowTrackContent();
        StatusLabel.Text = "正在加载你的曲库…";
        try
        {
            var page = await _api.GetTracksAsync(query);
            _tracks.Clear();
            foreach (var track in page.Items)
            {
                _tracks.Add(track);
            }
            StatusLabel.Text = string.IsNullOrWhiteSpace(query)
                ? $"已加载 {_tracks.Count} 首歌曲"
                : $"“{query}”找到 {_tracks.Count} 首歌曲";
        }
        catch (Exception exception) when (exception is SonaApiException or HttpRequestException or TaskCanceledException)
        {
            StatusLabel.Text = exception is TaskCanceledException ? "加载曲库超时" : exception.Message;
        }
    }

    private async void SearchBox_KeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            PageTitle.Text = "搜索";
            await LoadTracksAsync(SearchBox.Text ?? string.Empty);
        }
    }

    private async void Refresh_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
        => await LoadTracksAsync(SearchBox.Text ?? string.Empty);

    private async void Track_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (sender is Button { DataContext: Track track })
        {
            SetQueue(track);
            await PlayTrackAsync(track);
        }
    }

    private void SetQueue(Track selected)
    {
        _queue.Clear();
        foreach (var track in _tracks)
        {
            _queue.Add(track);
        }
        _currentIndex = _queue.IndexOf(selected);
        QueueCountLabel.Text = $"{_queue.Count} 首";
    }

    private async Task PlayTrackAsync(Track track)
    {
        _currentTrack = track;
        NowTitle.Text = track.Title;
        NowArtist.Text = track.Artist;
        QualityLabel.Text = track.QualityText;
        PlayPauseButton.Content = "Ⅱ";
        try
        {
            await _player.PlayAsync(track, _api);
        }
        catch (Exception exception)
        {
            StatusLabel.Text = $"播放失败：{exception.Message}";
            PlayPauseButton.Content = "▶";
        }
    }

    private void PlayPause_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (_currentTrack is null)
        {
            return;
        }
        _player.TogglePause();
        PlayPauseButton.Content = _player.IsPlaying ? "Ⅱ" : "▶";
    }

    private async void Previous_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (_queue.Count == 0)
        {
            return;
        }
        _currentIndex = (_currentIndex - 1 + _queue.Count) % _queue.Count;
        await PlayTrackAsync(_queue[_currentIndex]);
    }

    private async void Next_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
        => await PlayNextAsync();

    private async Task PlayNextAsync()
    {
        if (_queue.Count == 0)
        {
            return;
        }
        _currentIndex = (_currentIndex + 1) % _queue.Count;
        await PlayTrackAsync(_queue[_currentIndex]);
    }

    private async void Home_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        PageTitle.Text = "首页";
        SearchBox.Text = string.Empty;
        await LoadTracksAsync();
    }

    private async void Discovery_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        PageTitle.Text = "发现";
        ShowTrackContent();
        StatusLabel.Text = "正在加载发现池…";
        try
        {
            ReplaceTracks(await _api.GetDiscoveryTracksAsync());
            StatusLabel.Text = $"为你发现 {_tracks.Count} 首歌曲";
        }
        catch (Exception exception) when (exception is SonaApiException or HttpRequestException or TaskCanceledException)
        {
            StatusLabel.Text = exception is TaskCanceledException ? "加载发现池超时" : exception.Message;
        }
    }

    private void SearchNav_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        PageTitle.Text = "搜索";
        SearchBox.Focus();
    }

    private async void Library_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        PageTitle.Text = "音乐库";
        await LoadTracksAsync();
    }

    private async void Favorites_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        PageTitle.Text = "收藏的歌曲";
        ShowTrackContent();
        StatusLabel.Text = "正在加载收藏…";
        try
        {
            var page = await _api.GetFavoriteTracksAsync();
            ReplaceTracks(page.Items);
            StatusLabel.Text = $"收藏了 {_tracks.Count} 首歌曲";
        }
        catch (Exception exception) when (exception is SonaApiException or HttpRequestException or TaskCanceledException)
        {
            StatusLabel.Text = exception is TaskCanceledException ? "加载收藏超时" : exception.Message;
        }
    }

    private void Settings_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        PageTitle.Text = "设置";
        SettingsServerLabel.Text = _api.ServerUri.ToString().TrimEnd('/');
        SettingsUserLabel.Text = _user is null ? "未登录" : $"{_user.Username} · {_user.RoleTitle}";
        TracksList.IsVisible = false;
        SettingsPanel.IsVisible = true;
    }

    private async void Logout_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        _player.Stop();
        try
        {
            await _api.LogoutAsync();
        }
        catch (Exception exception) when (exception is SonaApiException or HttpRequestException or TaskCanceledException)
        {
            StatusLabel.Text = $"退出登录请求失败：{exception.Message}";
        }
        _user = null;
        _tracks.Clear();
        _queue.Clear();
        PasswordBox.Text = string.Empty;
        Shell.IsVisible = false;
        LoginPanel.IsVisible = true;
    }

    private void ShowLoginError(string message)
    {
        LoginError.Text = message;
        LoginError.IsVisible = true;
    }

    private void ShowTrackContent()
    {
        SettingsPanel.IsVisible = false;
        TracksList.IsVisible = true;
    }

    private void ReplaceTracks(IEnumerable<Track> tracks)
    {
        _tracks.Clear();
        foreach (var track in tracks)
        {
            _tracks.Add(track);
        }
    }
}
