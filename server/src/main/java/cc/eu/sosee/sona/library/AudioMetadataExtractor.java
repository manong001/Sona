package cc.eu.sosee.sona.library;

import java.nio.file.Path;

interface AudioMetadataExtractor {

    AudioMetadata extract(Path path) throws Exception;
}

