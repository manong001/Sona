namespace Sona.Windows.Models;

public sealed record Track(
    string Id,
    string Title,
    string Artist,
    string Album,
    int? TrackNumber,
    long DurationMs,
    string Codec,
    string FileExtension,
    int? SampleRate,
    int? BitDepth,
    string? ArtworkURL,
    string StreamURL,
    bool HasLyrics,
    string MetadataStatus,
    string PoolType,
    string AudienceType,
    string Genre,
    IReadOnlyList<string>? RelatedGenres,
    string Region,
    IReadOnlyList<string>? Artists)
{
    public string DurationText
    {
        get
        {
            var seconds = Math.Max(0, DurationMs / 1000);
            return $"{seconds / 60}:{seconds % 60:00}";
        }
    }

    public string QualityText
    {
        get
        {
            var parts = new List<string> { Codec };
            if (SampleRate is not null)
            {
                parts.Add($"{SampleRate.Value / 1000d:0.#} kHz");
            }
            if (BitDepth is not null)
            {
                parts.Add($"{BitDepth}-bit");
            }
            return string.Join(" · ", parts);
        }
    }
}

public sealed record TrackPage(IReadOnlyList<Track> Items, string? NextCursor);
