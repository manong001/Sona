package cc.eu.sosee.sona.library;

import java.nio.file.Path;

interface AudioFeatureExtractor {

    AudioFeatures extract(Path path) throws Exception;
}
