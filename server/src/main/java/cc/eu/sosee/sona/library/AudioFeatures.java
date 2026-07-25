package cc.eu.sosee.sona.library;

import java.util.Arrays;

record AudioFeatures(double[] vector, double tempoBpm, double energy) {

    static final int VERSION = 1;

    AudioFeatures {
        vector = Arrays.copyOf(vector, vector.length);
        tempoBpm = Math.max(0, tempoBpm);
        energy = Math.max(0, Math.min(energy, 1));
    }

    AudioFeatures(double[] vector) {
        this(vector, 0, 0);
    }

    @Override
    public double[] vector() {
        return Arrays.copyOf(vector, vector.length);
    }
}
