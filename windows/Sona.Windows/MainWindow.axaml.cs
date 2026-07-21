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
    private readonly AudioPlayerService _previewPlayer = new();
    private readonly ObservableCollection<Track> _tracks = [];
    private readonly ObservableCollection<Track> _queue = [];
    private readonly ObservableCollection<DuplicateTrackGroup> _duplicateGroups = [];
    private User? _user;
    private Track? _currentTrack;
    private DuplicateTrackItem? _pendingDuplicateDeletion;
    private string? _previewTrackId;
    private bool _resumeMainPlayerAfterPreview;
    private int _currentIndex = -1;

    public MainWindow()
    {
        InitializeComponent();
        TracksList.ItemsSource = _tracks;
        QueueList.ItemsSource = _queue;
        DuplicateGroupsList.ItemsSource = _duplicateGroups;
        _player.PlaybackEnded += (_, _) => Dispatcher.UIThread.Post(() => _ = PlayNextAsync());
        _player.PlaybackFailed += (_, _) => Dispatcher.UIThread.Post(() =>
        {
            StatusLabel.Text = "播放失败：LibVLC 无法解码当前音频流";
            PlayPauseButton.Content = "▶";
        });
        _previewPlayer.PlaybackEnded += (_, _) => Dispatcher.UIThread.Post(StopDuplicatePreview);
        _previewPlayer.PlaybackFailed += (_, _) => Dispatcher.UIThread.Post(() =>
        {
            StopDuplicatePreview();
            DuplicateStatusLabel.Text = "试听失败：LibVLC 无法解码当前音频流";
        });
        Closed += (_, _) =>
        {
            _player.Dispose();
            _previewPlayer.Dispose();
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
            DuplicateManagerButton.IsVisible = _user.IsAdmin;
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
        StopDuplicatePreview();
        PageTitle.Text = "设置";
        SettingsServerLabel.Text = _api.ServerUri.ToString().TrimEnd('/');
        SettingsUserLabel.Text = _user is null ? "未登录" : $"{_user.Username} · {_user.RoleTitle}";
        TracksList.IsVisible = false;
        DuplicatePanel.IsVisible = false;
        SettingsPanel.IsVisible = true;
    }

    private async void OpenDuplicates_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (_user?.IsAdmin != true)
        {
            return;
        }
        PageTitle.Text = "歌曲去重";
        SettingsPanel.IsVisible = false;
        TracksList.IsVisible = false;
        DuplicatePanel.IsVisible = true;
        await LoadDuplicatesAsync();
    }

    private void BackToSettings_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
        => Settings_Click(sender, e);

    private async void RefreshDuplicates_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
        => await LoadDuplicatesAsync();

    private async void DuplicatePreview_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: DuplicateTrackItem item })
        {
            return;
        }
        if (_previewTrackId == item.Track.Id)
        {
            StopDuplicatePreview();
            return;
        }
        StopDuplicatePreview();
        if (_player.IsPlaying)
        {
            _player.TogglePause();
            _resumeMainPlayerAfterPreview = true;
        }
        try
        {
            await _previewPlayer.PlayAsync(item.Track, _api);
            _previewTrackId = item.Track.Id;
            DuplicateStatusLabel.Text = $"正在试听：{item.Track.Artist} - {item.Track.Title}（未加入播放队列）";
        }
        catch (Exception exception) when (exception is SonaApiException or HttpRequestException
            or TaskCanceledException or InvalidOperationException or PlatformNotSupportedException)
        {
            StopDuplicatePreview();
            DuplicateStatusLabel.Text = $"试听失败：{exception.Message}";
        }
    }

    private void StopDuplicatePreview()
    {
        _previewPlayer.Stop();
        _previewTrackId = null;
        if (_resumeMainPlayerAfterPreview && !_player.IsPlaying)
        {
            _player.TogglePause();
        }
        _resumeMainPlayerAfterPreview = false;
        if (DuplicatePanel.IsVisible)
        {
            DuplicateStatusLabel.Text = "按标准化歌手和歌名列出；试听不会占用播放队列。";
        }
    }

    private async Task LoadDuplicatesAsync()
    {
        DuplicateEmptyLabel.Text = "正在检查重复歌曲…";
        DuplicateEmptyLabel.IsVisible = true;
        try
        {
            var groups = await _api.GetDuplicateTracksAsync();
            _duplicateGroups.Clear();
            foreach (var group in groups)
            {
                _duplicateGroups.Add(group);
            }
            DuplicateEmptyLabel.Text = "没有重复歌曲";
            DuplicateEmptyLabel.IsVisible = _duplicateGroups.Count == 0;
        }
        catch (Exception exception) when (exception is SonaApiException or HttpRequestException or TaskCanceledException)
        {
            DuplicateEmptyLabel.Text = exception is TaskCanceledException
                ? "检查重复歌曲超时"
                : exception.Message;
            DuplicateEmptyLabel.IsVisible = true;
        }
    }

    private void DuplicateDelete_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: DuplicateTrackItem item })
        {
            return;
        }
        _pendingDuplicateDeletion = item;
        var group = _duplicateGroups.First(group => group.Tracks.Any(track => track.Track.Id == item.Track.Id));
        ReplacementTargetsList.ItemsSource = group.Tracks.Where(track => track.Track.Id != item.Track.Id).ToList();
        ReplacementTargetsList.SelectedIndex = 0;
        DeleteConfirmDetails.Text = $"将永久删除：{item.Path}\n\n{item.UsersText}";
        DeleteConfirmOverlay.IsVisible = true;
    }

    private void CancelDuplicateDelete_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        _pendingDuplicateDeletion = null;
        ReplacementTargetsList.ItemsSource = null;
        DeleteConfirmOverlay.IsVisible = false;
    }

    private async void ConfirmDuplicateDelete_Click(
        object? sender,
        Avalonia.Interactivity.RoutedEventArgs e
    )
    {
        if (_pendingDuplicateDeletion is not { } item
            || ReplacementTargetsList.SelectedItem is not DuplicateTrackItem replacement)
        {
            return;
        }
        ConfirmDuplicateDeleteButton.IsEnabled = false;
        ConfirmDuplicateDeleteButton.Content = "正在删除…";
        try
        {
            StopDuplicatePreview();
            await _api.ReplaceDuplicateTrackAsync(item.Track.Id, replacement.Track.Id);
            _pendingDuplicateDeletion = null;
            ReplacementTargetsList.ItemsSource = null;
            DeleteConfirmOverlay.IsVisible = false;
            await LoadDuplicatesAsync();
        }
        catch (Exception exception) when (exception is SonaApiException or HttpRequestException or TaskCanceledException)
        {
            DeleteConfirmDetails.Text = $"删除失败：{exception.Message}\n\n文件：{item.Path}\n\n{item.UsersText}";
        }
        finally
        {
            ConfirmDuplicateDeleteButton.IsEnabled = true;
            ConfirmDuplicateDeleteButton.Content = "确认迁移并删除";
        }
    }

    private async void Logout_Click(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        StopDuplicatePreview();
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
        DuplicateManagerButton.IsVisible = false;
        _tracks.Clear();
        _queue.Clear();
        _duplicateGroups.Clear();
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
        DuplicatePanel.IsVisible = false;
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
