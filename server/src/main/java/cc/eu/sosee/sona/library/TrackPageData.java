package cc.eu.sosee.sona.library;

import java.util.List;

record TrackPageData(List<TrackRecord> items, String nextCursor) {
}

