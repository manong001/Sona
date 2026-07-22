package cc.eu.sosee.sona.library;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

@Component
class FfmpegAudioFeatureExtractor implements AudioFeatureExtractor {

    private static final int SAMPLE_RATE = 11_025;
    private static final int FRAME_SIZE = 512;
    private static final int MAX_SECONDS = 90;
    private static final double[] BAND_EDGES = {0, 100, 250, 500, 1_000, 2_000, 3_500, 5_513};

    @Override
    public AudioFeatures extract(Path path) throws Exception {
        var process = new ProcessBuilder(
            "ffmpeg", "-v", "error", "-nostdin", "-i", path.toString(),
            "-map", "0:a:0", "-ac", "1", "-ar", String.valueOf(SAMPLE_RATE),
            "-t", String.valueOf(MAX_SECONDS), "-f", "f32le", "pipe:1"
        ).start();
        AudioFeatures features;
        try (var output = process.getInputStream()) {
            features = extractPcm(output);
        }
        var error = readError(process.getErrorStream());
        var exitCode = process.waitFor();
        if (exitCode != 0) {
            throw new IOException("FFmpeg 音频解码失败" + (error.isBlank() ? "" : "：" + error));
        }
        return features;
    }

    AudioFeatures extractPcm(InputStream input) throws IOException {
        var frame = new double[FRAME_SIZE];
        var bytes = new byte[FRAME_SIZE * Float.BYTES];
        var rmsValues = new ArrayList<Double>();
        var featureSums = new double[12];
        var featureSquares = new double[2];
        var previousSpectrum = new double[FRAME_SIZE / 2];
        var frameCount = 0;
        while (true) {
            var byteCount = readFrame(input, bytes);
            if (byteCount == 0) break;
            var sampleCount = byteCount / Float.BYTES;
            decode(bytes, sampleCount, frame);
            applyHannWindow(frame, sampleCount);
            var rms = rms(frame, sampleCount);
            var zcr = zeroCrossingRate(frame, sampleCount);
            var spectrum = powerSpectrum(frame);
            var spectral = spectralFeatures(spectrum, previousSpectrum);
            var loudness = Math.log1p(rms * 100) / Math.log(101);
            rmsValues.add(rms);
            featureSums[0] += loudness;
            featureSquares[0] += loudness * loudness;
            featureSums[1] += zcr;
            featureSquares[1] += zcr * zcr;
            for (var index = 0; index < spectral.length; index++) {
                featureSums[index + 2] += spectral[index];
            }
            previousSpectrum = spectrum;
            frameCount++;
            if (byteCount < bytes.length) break;
        }
        if (frameCount == 0) throw new IOException("音频中没有可分析的 PCM 数据");

        var vector = new double[15];
        vector[0] = featureSums[0] / frameCount;
        vector[1] = standardDeviation(featureSums[0], featureSquares[0], frameCount);
        vector[2] = featureSums[1] / frameCount;
        vector[3] = standardDeviation(featureSums[1], featureSquares[1], frameCount);
        for (var index = 2; index < featureSums.length; index++) {
            vector[index + 2] = featureSums[index] / frameCount;
        }
        vector[14] = estimateTempo(rmsValues);
        normalize(vector);
        return new AudioFeatures(vector);
    }

    private int readFrame(InputStream input, byte[] bytes) throws IOException {
        var offset = 0;
        while (offset < bytes.length) {
            var count = input.read(bytes, offset, bytes.length - offset);
            if (count < 0) break;
            offset += count;
        }
        return offset - offset % Float.BYTES;
    }

    private void decode(byte[] bytes, int sampleCount, double[] samples) {
        var buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN);
        for (var index = 0; index < sampleCount; index++) {
            samples[index] = buffer.getFloat();
        }
        for (var index = sampleCount; index < samples.length; index++) samples[index] = 0;
    }

    private void applyHannWindow(double[] samples, int sampleCount) {
        for (var index = 0; index < sampleCount; index++) {
            samples[index] *= 0.5 - 0.5 * Math.cos(2 * Math.PI * index / (sampleCount - 1));
        }
    }

    private double rms(double[] samples, int sampleCount) {
        var sum = 0.0;
        for (var index = 0; index < sampleCount; index++) sum += samples[index] * samples[index];
        return Math.sqrt(sum / sampleCount);
    }

    private double zeroCrossingRate(double[] samples, int sampleCount) {
        var crossings = 0;
        for (var index = 1; index < sampleCount; index++) {
            if ((samples[index - 1] < 0) != (samples[index] < 0)) crossings++;
        }
        return crossings / (double) (sampleCount - 1);
    }

    private double[] powerSpectrum(double[] samples) {
        var real = samples.clone();
        var imaginary = new double[real.length];
        fft(real, imaginary);
        var power = new double[real.length / 2];
        for (var index = 0; index < power.length; index++) {
            power[index] = real[index] * real[index] + imaginary[index] * imaginary[index];
        }
        return power;
    }

    private double[] spectralFeatures(double[] spectrum, double[] previousSpectrum) {
        var result = new double[10];
        var total = 0.0;
        var weighted = 0.0;
        var flux = 0.0;
        for (var bin = 1; bin < spectrum.length; bin++) {
            var frequency = bin * SAMPLE_RATE / (double) FRAME_SIZE;
            var power = spectrum[bin];
            total += power;
            weighted += frequency * power;
            var increase = Math.sqrt(power) - Math.sqrt(previousSpectrum[bin]);
            if (increase > 0) flux += increase;
            for (var band = 0; band < BAND_EDGES.length - 1; band++) {
                if (frequency >= BAND_EDGES[band] && frequency < BAND_EDGES[band + 1]) {
                    result[band] += power;
                    break;
                }
            }
        }
        if (total <= 0) return result;
        for (var band = 0; band < BAND_EDGES.length - 1; band++) result[band] /= total;
        result[7] = weighted / total / (SAMPLE_RATE / 2.0);
        result[8] = rolloff(spectrum, total) / (SAMPLE_RATE / 2.0);
        result[9] = Math.log1p(flux) / 20.0;
        return result;
    }

    private double rolloff(double[] spectrum, double total) {
        var threshold = total * 0.85;
        var cumulative = 0.0;
        for (var bin = 1; bin < spectrum.length; bin++) {
            cumulative += spectrum[bin];
            if (cumulative >= threshold) return bin * SAMPLE_RATE / (double) FRAME_SIZE;
        }
        return SAMPLE_RATE / 2.0;
    }

    private double estimateTempo(List<Double> rmsValues) {
        if (rmsValues.size() < 16) return 0;
        var frameRate = SAMPLE_RATE / (double) FRAME_SIZE;
        var mean = rmsValues.stream().mapToDouble(Double::doubleValue).average().orElse(0);
        var bestScore = Double.NEGATIVE_INFINITY;
        var bestBpm = 0.0;
        for (var bpm = 60; bpm <= 200; bpm++) {
            var lag = (int) Math.round(frameRate * 60 / bpm);
            var score = 0.0;
            for (var index = lag; index < rmsValues.size(); index++) {
                score += (rmsValues.get(index) - mean) * (rmsValues.get(index - lag) - mean);
            }
            if (score > bestScore) {
                bestScore = score;
                bestBpm = bpm;
            }
        }
        return bestBpm / 200.0;
    }

    private double standardDeviation(double sum, double squareSum, int count) {
        var mean = sum / count;
        return Math.sqrt(Math.max(0, squareSum / count - mean * mean));
    }

    private void normalize(double[] vector) {
        var length = 0.0;
        for (var value : vector) length += value * value;
        length = Math.sqrt(length);
        if (length == 0) return;
        for (var index = 0; index < vector.length; index++) vector[index] /= length;
    }

    private void fft(double[] real, double[] imaginary) {
        var size = real.length;
        for (int index = 1, reversed = 0; index < size; index++) {
            var bit = size >> 1;
            while ((reversed & bit) != 0) {
                reversed ^= bit;
                bit >>= 1;
            }
            reversed ^= bit;
            if (index < reversed) {
                var realValue = real[index];
                real[index] = real[reversed];
                real[reversed] = realValue;
                var imaginaryValue = imaginary[index];
                imaginary[index] = imaginary[reversed];
                imaginary[reversed] = imaginaryValue;
            }
        }
        for (var length = 2; length <= size; length <<= 1) {
            var angle = -2 * Math.PI / length;
            var lengthReal = Math.cos(angle);
            var lengthImaginary = Math.sin(angle);
            for (var offset = 0; offset < size; offset += length) {
                var currentReal = 1.0;
                var currentImaginary = 0.0;
                for (var index = 0; index < length / 2; index++) {
                    var even = offset + index;
                    var odd = even + length / 2;
                    var oddReal = real[odd] * currentReal - imaginary[odd] * currentImaginary;
                    var oddImaginary = real[odd] * currentImaginary + imaginary[odd] * currentReal;
                    real[odd] = real[even] - oddReal;
                    imaginary[odd] = imaginary[even] - oddImaginary;
                    real[even] += oddReal;
                    imaginary[even] += oddImaginary;
                    var nextReal = currentReal * lengthReal - currentImaginary * lengthImaginary;
                    currentImaginary = currentReal * lengthImaginary + currentImaginary * lengthReal;
                    currentReal = nextReal;
                }
            }
        }
    }

    private String readError(InputStream input) throws IOException {
        try (input; var output = new ByteArrayOutputStream()) {
            input.transferTo(output);
            return output.toString().strip();
        }
    }
}
