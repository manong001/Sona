namespace Sona.Windows.Models;

public sealed record DuplicateTrackGroup(
    string Artist,
    string Title,
    IReadOnlyList<DuplicateTrackItem> Tracks)
{
    public string Header => $"{Artist} · {Title}（{Tracks.Count} 个文件）";
}

public sealed record DuplicateTrackItem(
    Track Track,
    string Path,
    long FileSize,
    IReadOnlyList<DuplicateTrackUsage> Users)
{
    public string VersionText => $"{Track.Album} · {Track.QualityText} · {Track.DurationText}";

    public string FileSizeText => FileSize switch
    {
        >= 1_073_741_824 => $"{FileSize / 1_073_741_824d:0.##} GB",
        >= 1_048_576 => $"{FileSize / 1_048_576d:0.##} MB",
        >= 1_024 => $"{FileSize / 1_024d:0.##} KB",
        _ => $"{FileSize} B"
    };

    public string UsersText => Users.Count == 0
        ? "没有用户引用"
        : string.Join(Environment.NewLine, Users.Select(user => user.Description));
}

public sealed record DuplicateTrackUsage(
    string UserId,
    string Username,
    bool Favorite,
    IReadOnlyList<string> Playlists,
    bool History,
    bool CurrentQueue)
{
    public string Description
    {
        get
        {
            var uses = new List<string>();
            if (Favorite) uses.Add("收藏");
            if (Playlists.Count > 0) uses.Add("歌单：" + string.Join("、", Playlists));
            if (History) uses.Add("播放历史");
            if (CurrentQueue) uses.Add("当前队列");
            return $"{Username}：{string.Join("，", uses)}";
        }
    }
}
