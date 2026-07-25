package cc.eu.sosee.sona.download;

import java.util.Optional;

interface PlaylistSubscriptionArtworkArchive {

    Optional<String> archive(String sourceUrl);

    byte[] read(String contentHash);
}
