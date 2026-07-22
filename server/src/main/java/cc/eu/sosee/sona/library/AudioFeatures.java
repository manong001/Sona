package cc.eu.sosee.sona.library;

import java.util.Arrays;

record AudioFeatures(double[] vector) {

    static final int VERSION = 1;

    AudioFeatures {
        vector = Arrays.copyOf(vector, vector.length);
    }

    @Override
    public double[] vector() {
        return Arrays.copyOf(vector, vector.length);
    }
}
