(
// ============================================================
// Plonk-ish v5.20
// - MULTI-TRACK DRUM SEQUENCER MODE
// - 4 tracks to start
// - each track has its own default sound
// - each track has its own independent step lane
// - playback triggers all active tracks each step
// - pattern UI edits one selected track at a time
// - presets removed
// ============================================================

// ---------- pre-boot server options ----------
s.options.memSize = 2097152;
s.options.numWireBufs = 512;

s.waitForBoot({

    // --------------------------------------------------------
    // paths
    // --------------------------------------------------------
    ~plonkEnsureDir = { |p|
        if(File.exists(p).not) {
            ("mkdir -p " ++ p.quote).unixCmd;
        };
    };

    ~plonkPatternDir = Platform.userHomeDir +/+ "PlonkPatterns";
    ~plonkEnsureDir.(~plonkPatternDir);

    // --------------------------------------------------------
    // helpers
    // --------------------------------------------------------
// --------------------------------------------------------
// contextual note spelling
// replace your old ~plonkMidiToName helper with this block
// --------------------------------------------------------

~plonkPcNamesSharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
~plonkPcNamesFlat  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];

~plonkLetterBasePc = (
    C: 0,
    D: 2,
    E: 4,
    F: 5,
    G: 7,
    A: 9,
    B: 11
);

~plonkScaleDegreeLetters = [\C, \D, \E, \F, \G, \A, \B];

~plonkKeyUsesSharps = { |rootPc, scaleType|
    var sharpRoots = [0, 1, 2, 4, 5, 7, 9, 11];   // C C# D E F G A B
    var flatRoots  = [3, 6, 8, 10];               // Eb Gb Ab Bb
    var useSharps = true;

    // keep explicit preferences for common flat spellings
    if(flatRoots.includes(rootPc)) { useSharps = false };
    if(sharpRoots.includes(rootPc)) { useSharps = true };

    // some modal/minor contexts are usually flatter
    if(scaleType == 2) { // minor
        if([3, 5, 8, 10].includes(rootPc)) { useSharps = false };
    };

    if(scaleType == 3) { // dorian
        if([3, 5, 8, 10].includes(rootPc)) { useSharps = false };
    };

    if(scaleType == 4) { // mixolydian
        if([3, 8, 10].includes(rootPc)) { useSharps = false };
    };

    useSharps;
};

~plonkParentHeptatonicScaleType = { |scaleType|
    switch(scaleType,
        5, { 1 }, // Pent Major -> Major
        6, { 2 }, // Pent Minor -> Minor
        { scaleType }
    )
};

~plonkBuildScaleSpelling = { |rootPc, scaleType|
    var useSharps, rootName, rootLetterChar, rootLetter, rootIndex;
    var parentScaleType, intervals, letters, names, pcs;
    var naturalPc, targetPc, diff, accStr;

    rootPc = rootPc.asInteger.clip(0, 11);
    parentScaleType = ~plonkParentHeptatonicScaleType.(scaleType.asInteger);
    useSharps = ~plonkKeyUsesSharps.(rootPc, parentScaleType);

    rootName = if(useSharps) {
        ~plonkPcNamesSharp[rootPc]
    }{
        ~plonkPcNamesFlat[rootPc]
    };

    rootLetterChar = rootName[0].asString;
    rootLetter = rootLetterChar.asSymbol;
    rootIndex = ~plonkScaleDegreeLetters.indexOf(rootLetter);
    if(rootIndex.isNil) { rootIndex = 0 };

    intervals = switch(parentScaleType,
        1, { [0, 2, 4, 5, 7, 9, 11] }, // Major
        2, { [0, 2, 3, 5, 7, 8, 10] }, // Minor
        3, { [0, 2, 3, 5, 7, 9, 10] }, // Dorian
        4, { [0, 2, 4, 5, 7, 9, 10] }, // Mixolydian
        { [0, 2, 4, 5, 7, 9, 11] }     // fallback Major
    );

    letters = Array.fill(7, { |i|
        ~plonkScaleDegreeLetters.wrapAt(rootIndex + i)
    });

    names = Array.fill(7, { |i|
        var letter = letters[i];
        naturalPc = ~plonkLetterBasePc[letter];
        targetPc = (rootPc + intervals[i]) % 12;
        diff = (targetPc - naturalPc) % 12;

        accStr = switch(diff,
            0, { "" },
            1, { "#" },
            2, { "##" },
            11, { "b" },
            10, { "bb" },
            { "" }
        );

        letter.asString ++ accStr
    });

    pcs = intervals.collect { |iv| (rootPc + iv) % 12 };

    (
        rootPc: rootPc,
        scaleType: scaleType,
        parentScaleType: parentScaleType,
        useSharps: useSharps,
        pcs: pcs,
        names: names
    )
};

~plonkSpellPitchClassInContext = { |pc, spelling|
    var idx, useSharps;

    pc = pc.asInteger % 12;
    spelling = spelling ? ~plonkBuildScaleSpelling.(0, 1);

    idx = spelling[\pcs].indexOf(pc);
    if(idx.notNil) {
        spelling[\names][idx]
    }{
        useSharps = spelling[\useSharps] ? true;
        if(useSharps) {
            ~plonkPcNamesSharp[pc]
        }{
            ~plonkPcNamesFlat[pc]
        }
    }
};

~plonkMidiToName = { |num|
    var midi, octave, pc, spelling, noteName;

    midi = num.asInteger.clip(0, 127);
    pc = midi % 12;
    octave = (midi div: 12) - 1;

    spelling = ~plonkBuildScaleSpelling.(
        (~plonkPitch[\root] ? 0).asInteger,
        (~plonkPitch[\scaleType] ? 0).asInteger
    );

    noteName = if((~plonkPitch[\scaleType] ? 0).asInteger == 0) {
        // chromatic mode: just use sharp/flat preference
        if(spelling[\useSharps]) {
            ~plonkPcNamesSharp[pc]
        }{
            ~plonkPcNamesFlat[pc]
        }
    }{
        ~plonkSpellPitchClassInContext.(pc, spelling)
    };

    noteName ++ octave.asString
};

    ~plonkNoteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

    ~plonkScaleNames = [
        "Chromatic",
        "Major",
        "Minor",
        "Dorian",
        "Mixolydian",
        "Pent Major",
        "Pent Minor"
    ];

    ~plonkScaleTable = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
        [0, 2, 4, 5, 7, 9, 11],
        [0, 2, 3, 5, 7, 8, 10],
        [0, 2, 3, 5, 7, 9, 10],
        [0, 2, 4, 5, 7, 9, 10],
        [0, 2, 4, 7, 9],
        [0, 3, 5, 7, 10]
    ];

    ~plonkLayerModeNames = ["Single", "Layer", "Alt", "Random"];
	~plonkRandSelModeNames = ["Full", "Selection", "Timing", "Pitch", "Accent", "Layer"];
	~plonkSynth2TypeNames = ["FM Burst", "PWM Buzz", "Ring Metal", "Vowel Noise"];
		~plonkSynth2VariantNames = ["Soft", "Bright", "Wide", "Hollow", "Nasal", "Harsh"];
		~plonkSynth2PitchModeNames = ["Follow", "Semi", "Degree"];

    ~plonkPitch = (
        root: 0,
        scaleType: 0
    );

    ~plonkCondNames = [
        "Always", "1:2", "2:2", "1:4", "2:4", "3:4", "4:4",
        "Fill", "First", "NotPrev", "Prev", "EveryN"
    ];

    ~plonkCondShortName = { |step|
        var t = step[\condType] ? 0;
        var a = step[\condA] ? 1;
        var b = step[\condB] ? 2;

        switch(t,
            0, { "A" },
            1, { "1:2" },
            2, { "2:2" },
            3, { "1:4" },
            4, { "2:4" },
            5, { "3:4" },
            6, { "4:4" },
            7, { "FIL" },
            8, { "1ST" },
            9, { "!PR" },
            10, { "PRV" },
            11, { a.asString ++ ":" ++ b.asString },
            { "A" }
        )
    };

    ~plonkQuantizeMidi = { |midi|
        var root = (~plonkPitch[\root] ? 0).asInteger.clip(0, 11);
        var scaleType = (~plonkPitch[\scaleType] ? 0).asInteger.clip(0, ~plonkScaleTable.size - 1);
        var intervals = ~plonkScaleTable[scaleType];
        var m = midi.asInteger.clip(0, 127);
        var best = m;
        var bestDist = 9999;

        if(scaleType == 0) {
            m;
        }{
            (-2).to(10, { |oct|
                intervals.do { |iv|
                    var cand = (root + iv + (oct * 12)).asInteger;
                    var dist;
                    if((cand >= 0) and: { cand <= 127 }) {
                        dist = (cand - m).abs;
                        if(
                            (dist < bestDist) or:
                            { (dist == bestDist) and: { cand < best } }
                        ) {
                            bestDist = dist;
                            best = cand;
                        };
                    };
                };
            });
            best.clip(0, 127);
        };
    };


	~plonkRootAlignedBaseMidi = { |baseMidi|
    var base = (baseMidi ? (~plonkSeq[\baseMidi] ? 48)).asInteger.clip(0, 127);
    var root = (~plonkPitch[\root] ? 0).asInteger.clip(0, 11);
    var offsetUp = (root - (base % 12)) % 12;
    (base + offsetUp).clip(0, 127);
};

    ~plonkDegreeToMidi = { |degree=0, degreeOct=0|
    var scaleType = (~plonkPitch[\scaleType] ? 0).asInteger.clip(0, ~plonkScaleTable.size - 1);
    var intervals = ~plonkScaleTable[scaleType];
    var deg = degree.asInteger;
    var oct = degreeOct.asInteger;
    var size = intervals.size.max(1);
    var wrappedIndex, extraOct, interval;
    var tonicBase;

    if(scaleType == 0) {
        (~plonkSeq[\baseMidi] + deg + (oct * 12)).clip(0, 127);
    }{
        tonicBase = ~plonkRootAlignedBaseMidi.(~plonkSeq[\baseMidi]);

        if(deg >= 0) {
            extraOct = deg div: size;
            wrappedIndex = deg % size;
        }{
            extraOct = ((deg + 1) div: size) - 1;
            wrappedIndex = deg - (extraOct * size);
        };

        interval = intervals.wrapAt(wrappedIndex);
        (tonicBase + interval + ((oct + extraOct) * 12)).clip(0, 127);
    };
};

    // --------------------------------------------------------
    // synth definition
    // --------------------------------------------------------
    ~plonkDefineSynth = {
        SynthDef(\plonkV520, {
            |out=0, amp=0.22, pan=0,
            freq=220, gate=1, velocity=0.9,
            model=0,
            exciterType=0,
            brightness=0.65,
            material=0.55,
            inharm=0.22,
            position=0.22,
            decay=1.2,
            body=0.45,
            damp=0.25,
            drive=1.15,
            tone=0.58,
            noiseAmt=0.32,
            clickAmt=0.82,
            excDecay=0.025,
            detune=0.0025,
            spread=1.0,
            pitchEnvAmt=0.0,
            pitchEnvDecay=0.03,
            velToBright=0.35,
            velToDecay=0.2,
            velToNoise=0.2,
            velToClick=0.2,
			filterMode=0,
			filterCutoff=0.65,
			filterRes=0.25,
			filterEnvAmt=0.35,
			filterEnvDecay=0.08,
			combAmt=0.0,
			combTime=0.008,
			combDecay=0.18,
			edgeDrive=1.0,
			foldAmt=0.0,
			presence=0.0,
			crushMix=0.0,
			bitDepth=12,
			downsample=1|

            var ampEnv, excEnv, pitchEnv;
            var baseFreq, effBright, effDecay, effNoise, effClick;
            var mallet, hardPick, brush, scrape, burst, impulseCluster, exciter;
            var sigA, sigB, sig, bodySig;
            var numModes = 12;
            var strikeShape, brightScale, lowBoost;
            var modelPartialsA, modelPartialsB;
            var ampShapeA, ampShapeB, ringShapeA, ringShapeB;
            var mkBank, bankA, bankB;
			var filterEnv, filtFreq, filtRq, filtered, comb, folded, crushed, ds, bits, step;

            pitchEnv = EnvGen.kr(
                Env([1 + pitchEnvAmt, 1], [pitchEnvDecay], curve: -6)
            );

			filterEnv = EnvGen.kr(
    Env([1 + filterEnvAmt.clip(0, 4), 1], [filterEnvDecay.clip(0.005, 1.5)], curve: -6)
);

            baseFreq = freq * pitchEnv;

            effBright = (brightness + ((velocity - 0.5) * 2 * velToBright)).clip(0, 1);
            effDecay  = (decay * (1 + ((velocity - 0.5) * 2 * velToDecay))).clip(0.03, 6.0);
            effNoise  = (noiseAmt + ((velocity - 0.5) * 2 * velToNoise)).clip(0, 1.2);
            effClick  = (clickAmt + ((velocity - 0.5) * 2 * velToClick)).clip(0, 2.0);

            excEnv = EnvGen.kr(Env.perc(0.0006, excDecay.clip(0.001, 0.2), curve: -4));
            ampEnv = EnvGen.kr(Env.asr(0.001, 1, effDecay, curve: -4), gate, doneAction: 2);

            mallet = LPF.ar(WhiteNoise.ar(effNoise * 0.55), tone.linexp(0, 1, 1200, 9000))
                + Decay2.ar(Impulse.ar(0), 0.0004, 0.003) * effClick * 0.9;
            mallet = mallet * EnvGen.kr(Env.perc(0.0004, excDecay * 1.0, curve: -5));

            hardPick = HPF.ar(WhiteNoise.ar(effNoise * 0.25), 1800)
                + Decay2.ar(Impulse.ar(0), 0.00015, 0.0016) * effClick * 1.25;
            hardPick = hardPick * EnvGen.kr(Env.perc(0.0002, excDecay * 0.65, curve: -7));

            brush = LPF.ar(PinkNoise.ar(effNoise * 0.85), tone.linexp(0, 1, 900, 7000));
            brush = brush * EnvGen.kr(Env.perc(0.001, excDecay * 1.7, curve: -2));

            scrape = HPF.ar(WhiteNoise.ar(effNoise * 0.9), 1400);
            scrape = BPF.ar(scrape, tone.linexp(0, 1, 1800, 10000), 0.45);
            scrape = scrape * EnvGen.kr(Env.perc(0.0008, excDecay * 2.0, curve: -1));

            burst = BPF.ar(WhiteNoise.ar(effNoise * 0.75), tone.linexp(0, 1, 500, 8000), 0.5)
                + Decay2.ar(Impulse.ar(0), 0.00025, 0.0022) * effClick * 0.55;
            burst = burst * EnvGen.kr(Env.perc(0.0004, excDecay * 0.9, curve: -4));

            impulseCluster = Mix.fill(4, { |i|
                DelayN.ar(
                    Decay2.ar(Impulse.ar(0), 0.00012, 0.0012 + (i * 0.00022)) * (effClick * (1 - (i * 0.12))),
                    0.02,
                    [0.0, 0.0015, 0.0033, 0.0052].wrapAt(i)
                )
            }) + HPF.ar(WhiteNoise.ar(effNoise * 0.18), 2500);
            impulseCluster = impulseCluster * EnvGen.kr(Env.perc(0.0002, excDecay * 0.7, curve: -6));

            exciter = SelectX.ar(exciterType.clip(0, 5), [
                mallet, hardPick, brush, scrape, burst, impulseCluster
            ]);

            exciter = HPF.ar(exciter * excEnv * velocity, 25);
            exciter = tanh(exciter * drive);

            modelPartialsA = Select.kr(model.clip(0, 3), [
                [1.00, 2.76, 5.40, 8.93, 13.34, 18.64, 24.83, 31.92, 39.91, 48.80, 58.59, 69.28],
                [1.00, 1.63, 2.31, 2.92, 3.58, 4.21, 4.86, 5.53, 6.19, 6.88, 7.56, 8.24],
                [1.00, 2.01, 2.97, 4.11, 5.43, 6.80, 8.21, 9.69, 11.20, 12.78, 14.40, 16.05],
                [1.00, 1.59, 2.14, 2.30, 2.92, 3.45, 3.92, 4.50, 5.10, 5.76, 6.35, 6.98]
            ]);

            modelPartialsB = Select.kr(model.clip(0, 3), [
                [1.00, 3.99, 9.30, 16.71, 26.22, 37.83, 51.54, 67.35, 85.26, 105.27, 127.38, 151.59],
                [1.00, 1.41, 1.99, 2.58, 3.16, 3.73, 4.33, 4.91, 5.51, 6.11, 6.72, 7.34],
                [0.50, 1.34, 2.72, 3.88, 5.02, 6.17, 7.51, 8.93, 10.40, 11.94, 13.53, 15.18],
                [0.84, 1.28, 1.83, 2.41, 2.77, 3.18, 3.74, 4.12, 4.69, 5.31, 5.89, 6.42]
            ]);

            strikeShape = Array.fill(numModes, { |i|
                var n = i + 1;
                sin(pi * n * position.clip(0.01, 0.49)).abs.pow(spread.clip(0.25, 4.5)).max(0.0001)
            });

            brightScale = Array.fill(numModes, { |i|
                var norm = i / (numModes - 1).max(1);
                ((1 - norm).blend(norm, effBright)).linlin(0, 1, 1.0, 0.18)
            });

            lowBoost = Array.fill(numModes, { |i|
                var norm = i / (numModes - 1).max(1);
                (1.0 - (norm * 0.35)).clip(0.25, 1.0)
            });

            ampShapeA = Select.kr(model.clip(0, 3), [
                [1.00, 0.80, 0.65, 0.52, 0.42, 0.34, 0.28, 0.23, 0.19, 0.16, 0.13, 0.11],
                [1.00, 0.94, 0.88, 0.80, 0.72, 0.66, 0.60, 0.54, 0.49, 0.44, 0.40, 0.36],
                [1.00, 0.85, 0.76, 0.88, 0.70, 0.60, 0.52, 0.46, 0.40, 0.35, 0.31, 0.28],
                [1.00, 0.52, 0.84, 0.46, 0.58, 0.36, 0.28, 0.23, 0.19, 0.16, 0.14, 0.12]
            ]);

            ampShapeB = Select.kr(model.clip(0, 3), [
                [0.42, 0.34, 0.27, 0.22, 0.18, 0.15, 0.12, 0.10, 0.085, 0.072, 0.061, 0.052],
                [0.65, 0.60, 0.56, 0.52, 0.47, 0.43, 0.39, 0.35, 0.31, 0.28, 0.25, 0.22],
                [0.32, 0.44, 0.52, 0.46, 0.39, 0.34, 0.30, 0.26, 0.23, 0.20, 0.18, 0.16],
                [0.54, 0.38, 0.42, 0.28, 0.24, 0.20, 0.17, 0.145, 0.125, 0.108, 0.094, 0.082]
            ]);

            ringShapeA = Select.kr(model.clip(0, 3), [
                [1.00, 0.90, 0.82, 0.75, 0.69, 0.63, 0.58, 0.53, 0.49, 0.45, 0.41, 0.38],
                [1.00, 0.97, 0.94, 0.91, 0.88, 0.84, 0.80, 0.76, 0.72, 0.68, 0.64, 0.60],
                [1.00, 1.00, 0.98, 0.97, 0.95, 0.94, 0.92, 0.90, 0.88, 0.86, 0.84, 0.82],
                [1.00, 0.78, 0.68, 0.60, 0.54, 0.49, 0.44, 0.40, 0.36, 0.33, 0.30, 0.27]
            ]);

            ringShapeB = Select.kr(model.clip(0, 3), [
                [0.55, 0.48, 0.42, 0.37, 0.33, 0.29, 0.26, 0.23, 0.21, 0.19, 0.17, 0.15],
                [0.78, 0.76, 0.74, 0.72, 0.69, 0.66, 0.63, 0.60, 0.57, 0.54, 0.51, 0.48],
                [0.92, 0.90, 0.88, 0.86, 0.84, 0.82, 0.80, 0.78, 0.76, 0.74, 0.72, 0.70],
                [0.42, 0.39, 0.36, 0.33, 0.30, 0.27, 0.24, 0.22, 0.20, 0.18, 0.16, 0.145]
            ]);

            mkBank = { |partials, ampShape, ringShape, bankLevel=1.0, bankDetune=0.0|
                var freqs, amps, rings;

                freqs = Array.fill(numModes, { |i|
                    var p = partials.wrapAt(i);
                    var harmBlend = ((i + 1).asFloat).blend(p, material.clip(0, 1));
                    var norm = i / (numModes - 1).max(1);
                    var stretch = 1 + (inharm.clip(0, 0.8) * norm.squared * 1.8);
                    (baseFreq * harmBlend * stretch * (1 + Rand((detune + bankDetune).neg, (detune + bankDetune)))).clip(20, 20000)
                });

                amps = Array.fill(numModes, { |i|
                    (ampShape.wrapAt(i) * strikeShape.wrapAt(i) * brightScale.wrapAt(i) * lowBoost.wrapAt(i) * bankLevel).max(0.0001)
                });

                rings = Array.fill(numModes, { |i|
                    var base = effDecay * ringShape.wrapAt(i);
                    var dampScale = 1 / ((i + 1).pow(damp.linlin(0, 1, 0.0, 0.6)));
                    (base * dampScale).clip(0.03, 6.0)
                });

                [freqs, amps, rings];
            };

            bankA = mkBank.(modelPartialsA, ampShapeA, ringShapeA, 1.0, 0.0);
            bankB = mkBank.(modelPartialsB, ampShapeB, ringShapeB, 0.62, 0.0009);

            sigA = DynKlank.ar(`[bankA[0], bankA[1], bankA[2]], exciter);
            sigB = DynKlank.ar(`[bankB[0], bankB[1], bankB[2]], exciter * 0.8);
            sig = sigA + sigB;

            bodySig = SelectX.ar(model.clip(0, 3), [
                BPF.ar(sig, baseFreq * 1.15, 0.22, body * 0.24) + BPF.ar(sig, baseFreq * 0.78, 0.18, body * 0.12),
                BPF.ar(sig, baseFreq * 1.8, 0.34, body * 0.16) + BPF.ar(sig, baseFreq * 3.4, 0.42, body * 0.12),
                BPF.ar(sig, baseFreq * 2.3, 0.16, body * 0.14) + BPF.ar(sig, baseFreq * 4.7, 0.14, body * 0.10),
                BPF.ar(sig, baseFreq * 0.94, 0.42, body * 0.34) + BPF.ar(sig, baseFreq * 1.65, 0.36, body * 0.18)
            ]);

sig = sig + bodySig;

// ----------------------------------------------------
// multimode filter with env
// ----------------------------------------------------
filtFreq = (filterCutoff.clip(0, 1).linexp(0, 1, 120, 16000) * filterEnv).clip(40, 20000);
filtRq = filterRes.clip(0.01, 0.98).linlin(0.01, 0.98, 0.95, 0.08);

filtered = SelectX.ar(filterMode.clip(0, 3), [
    RLPF.ar(sig, filtFreq, filtRq),              // 0 LP
    RHPF.ar(sig, filtFreq, filtRq),              // 1 HP
    BPF.ar(sig, filtFreq, filtRq.clip(0.08, 1)), // 2 BP
    BRF.ar(sig, filtFreq, filtRq.clip(0.08, 1))  // 3 Notch
]);

sig = XFade2.ar(sig, filtered, 0.25);

// ----------------------------------------------------
// cavity / comb body
// ----------------------------------------------------
comb = CombC.ar(
    sig,
    0.05,
    combTime.clip(0.0007, 0.03),
    combDecay.clip(0.02, 2.0)
);
comb = LPF.ar(comb, filtFreq.clip(200, 14000));
sig = sig + (comb * combAmt.clip(0, 1));

// ----------------------------------------------------
// edge shaping
// ----------------------------------------------------
sig = LeakDC.ar(sig);
sig = tanh(sig * (1 + (drive * 0.5)));
sig = tanh(sig * edgeDrive.clip(0.5, 8.0));

folded = Fold.ar(sig * (1 + (foldAmt.clip(0, 1) * 6)), -1, 1);
sig = SelectX.ar(foldAmt.clip(0, 1), [sig, folded]);

sig = BPeakEQ.ar(
    sig,
    3200,
    0.6,
    presence.clip(-1, 1).linlin(-1, 1, -10, 12)
);

// ----------------------------------------------------
// digital crush layer
// ----------------------------------------------------
bits = bitDepth.clip(2, 16);
step = 2 ** (bits.neg + 1);
crushed = (sig / step).round * step;

ds = downsample.clip(1, 24).round.asInteger;
crushed = Latch.ar(crushed, Impulse.ar(SampleRate.ir / ds.max(1)));

sig = XFade2.ar(sig, crushed, crushMix.clip(0, 1).linlin(0, 1, -1, 1));

// ----------------------------------------------------
// final tone
// ----------------------------------------------------
sig = LPF.ar(sig, effBright.linexp(0, 1, 2500, 18000));
sig = HPF.ar(sig, 28);
sig = LeakDC.ar(sig);
sig = sig * amp * ampEnv;

            Out.ar(out, Pan2.ar(sig, pan));
        }).add;

		SynthDef(\plonkV520Layer2, {
    |out=0, amp=0.12, pan=0,
    freq=220, gate=1, velocity=0.9,
    synthType=0,
    color=0.5,
    motion=0.25,
    decay=0.25,
    drive=1.4,
    noise=0.0,
    click=0.0,
    pwmWidth=0.35,
    fmRatio=2.0,
    fmIndex=2.0,
    formantMorph=0.3,
    ringMix=0.5,
    unisonVoices=1,
    unisonDetune=0.0,
    unisonStereo=0.0,
    unisonDrift=0.0,
	pitchEnvAmt=0.0,
    pitchEnvDecay=0.03,
    pitchEnvCurve=(-6)|

    var ampEnv, pitchEnv, attack;
    var voiceCount, detAmt, stereoAmt, driftAmt;
    var panPos;
    var activeMask;
    var mkVoice, sig;

        ampEnv = EnvGen.kr(
        Env.asr(0.001, 1, decay.clip(0.02, 2.0), curve: -4),
        gate,
        doneAction: 2
    );

    pitchEnv = EnvGen.kr(
        Env(
            [1 + pitchEnvAmt, 1],
            [pitchEnvDecay.clip(0.001, 1.5)],
            curve: pitchEnvCurve.clip(-12, 12)
        )
    );


    attack = Decay2.ar(
        Impulse.ar(0),
        0.0002,
        0.002 + (click.abs * 0.004)
    ) * (0.12 + (click.abs * 0.25));
    attack = HPF.ar(attack, 1800);

    voiceCount = unisonVoices.clip(1, 4).round;
    detAmt = unisonDetune.clip(0, 0.5);   // semitones
    stereoAmt = unisonStereo.clip(0, 1);
    driftAmt = unisonDrift.clip(0, 1);

    mkVoice = { |i, spreadPos|
        var baseFreq, driftSemi, detSemi, voicePan;
        var fmSig, pwmSig, ringSig, vowelSig, voiceSig;
        var modFreq, modAmt, mod, widthMod;
        var form1, form2, noiseSrc, oscA, oscB;

        driftSemi = LFNoise2.kr(
            0.18 + (driftAmt * 3.8) + (i * 0.11)
        ).range(-0.08, 0.08) * driftAmt;

        detSemi = spreadPos * detAmt;
        baseFreq = freq * pitchEnv * (2 ** ((detSemi + driftSemi) / 12));
        voicePan = (pan + (spreadPos * stereoAmt * 0.8)).clip(-1, 1);

        // 0 = FM Burst
        modFreq = baseFreq * (fmRatio.clip(0.25, 10) + (motion * 1.5));
        modAmt = baseFreq * fmIndex.clip(0.1, 8) * (0.15 + (color * 0.85));
        mod = SinOsc.ar(modFreq, 0, modAmt);
        fmSig = SinOsc.ar(baseFreq + mod);
        fmSig = (fmSig * 0.6)
            + BPF.ar(fmSig, (baseFreq * (2 + color * 8)).clip(80, 16000), 0.4);

        // 1 = PWM Buzz
        widthMod = LFNoise2.kr(3 + (motion * 22) + (i * 0.07)).range(
            (0.04 + (color * 0.10)).neg,
            (0.04 + (color * 0.10))
        );

        pwmSig = Mix(Pulse.ar(
            baseFreq * [1, 1.0015 + (motion * 0.01), 1.997],
            (pwmWidth.clip(0.08, 0.92) + widthMod).clip(0.05, 0.95)
        )) * 0.33;

        pwmSig = HPF.ar(
            RLPF.ar(
                pwmSig,
                (baseFreq * (3 + color * 10)).clip(120, 18000),
                0.2
            ),
            50
        );

        // 2 = Ring Metal
        oscA = Saw.ar(baseFreq * (1 + (motion * 0.015)));
        oscB = SinOsc.ar(baseFreq * (1.5 + (color * 5.5) + (noise.abs * 1.5)));
        ringSig = oscA * oscB;
        ringSig = BPF.ar(
            ringSig,
            (baseFreq * (2.2 + (color * 9))).clip(100, 18000),
            0.25 + (motion * 0.2)
        );

        // 3 = Vowel / Formant Noise
        noiseSrc = PinkNoise.ar(0.7 + (noise.abs * 0.6));
        form1 = formantMorph.clip(0, 1).linexp(0, 1, 350, 1100);
        form2 = formantMorph.clip(0, 1).linexp(0, 1, 900, 3200);

        vowelSig = BPF.ar(noiseSrc, form1, 0.18, 0.9)
            + BPF.ar(noiseSrc, form2, 0.12, 0.75);

        vowelSig = vowelSig + (SinOsc.ar(baseFreq, 0, 0.15) * ringMix.clip(0, 1));
        vowelSig = HPF.ar(vowelSig, 100);

        voiceSig = SelectX.ar(synthType.clip(0, 3), [
            fmSig,
            pwmSig,
            ringSig,
            vowelSig
        ]);

        voiceSig = voiceSig + attack;

        voiceSig = voiceSig + LPF.ar(
            WhiteNoise.ar(noise.abs.clip(0, 1) * 0.08),
            (baseFreq * (6 + color * 12)).clip(500, 16000)
        );

        voiceSig = LeakDC.ar(voiceSig);
        voiceSig = tanh(voiceSig * drive.clip(0.6, 6.0));

        voiceSig = BPeakEQ.ar(
            voiceSig,
            (baseFreq * (4 + color * 8)).clip(800, 7000),
            0.5,
            velocity.linlin(0, 1, -2, 6)
        );

        voiceSig = HPF.ar(voiceSig, 35);
        Pan2.ar(voiceSig, voicePan);
    };

    panPos = [-1.5, -0.5, 0.5, 1.5] / 1.5;

    sig = Mix.fill(4, { |i|
        activeMask = Select.kr(i, [
            1,
            (voiceCount > 1),
            (voiceCount > 2),
            (voiceCount > 3)
        ]);
        mkVoice.(i, panPos[i]) * activeMask
    });

    sig = sig / voiceCount.sqrt.max(1);
    sig = sig * amp * ampEnv * velocity.linlin(0, 1, 0.35, 1.0);

    Out.ar(out, sig);
}).add;
    };

    ~plonkDefineSynth.();
    "Loaded \\plonkV520".postln;

    // --------------------------------------------------------
    // multi-track state
    // --------------------------------------------------------
    ~plonkTrackCount = 4;
    ~plonkTrackNames = ["Kick", "Snare", "Hat", "Perc"];
    ~plonkSelectedTrack = 0;

    ~plonkMakeTrackState = { |which=0|
        var st;

        st = (
            freq: 220, amp: 0.24, pan: 0, velocity: 0.90,
            model: 0, exciterType: 0,
            brightness: 0.65, material: 0.55, inharm: 0.22, position: 0.22,
            decay: 1.2, body: 0.45, damp: 0.25, drive: 1.15, tone: 0.58,
            noiseAmt: 0.32, clickAmt: 0.82, excDecay: 0.025, detune: 0.0025, spread: 1.0,
            pitchEnvAmt: 0.0, pitchEnvDecay: 0.03,
            velToBright: 0.35, velToDecay: 0.20, velToNoise: 0.20, velToClick: 0.20, filterMode: 0,
			filterCutoff: 0.65, filterRes: 0.25, filterEnvAmt: 0.35, filterEnvDecay: 0.08, combAmt: 0.0,
			combTime: 0.008, combDecay: 0.18, edgeDrive: 1.0, foldAmt: 0.0, presence: 0.0, crushMix: 0.0,
			bitDepth: 12, downsample: 1
        );

        switch(which,
            0, {
                st.putAll((
                    model: 3, exciterType: 1, amp: 0.34,
                    brightness: 0.22, material: 0.30, inharm: 0.08, position: 0.18,
                    decay: 0.95, body: 0.90, damp: 0.42, drive: 1.28, tone: 0.28,
                    noiseAmt: 0.12, clickAmt: 0.88, excDecay: 0.018, detune: 0.0012,
                    pitchEnvAmt: 0.18, pitchEnvDecay: 0.028
                ));
            },
            1, {
                st.putAll((
                    model: 1, exciterType: 4, amp: 0.26,
                    brightness: 0.78, material: 0.82, inharm: 0.24, position: 0.29,
                    decay: 0.78, body: 0.32, damp: 0.24, drive: 1.08, tone: 0.76,
                    noiseAmt: 0.34, clickAmt: 0.66, excDecay: 0.020, detune: 0.0020,
                    pitchEnvAmt: 0.02, pitchEnvDecay: 0.020
                ));
            },
            2, {
                st.putAll((
                    model: 2, exciterType: 5, amp: 0.14,
                    brightness: 0.95, material: 0.96, inharm: 0.36, position: 0.09,
                    decay: 0.22, body: 0.08, damp: 0.15, drive: 1.02, tone: 0.92,
                    noiseAmt: 0.22, clickAmt: 1.10, excDecay: 0.006, detune: 0.0008,
                    pitchEnvAmt: 0.0, pitchEnvDecay: 0.012
                ));
            },
            3, {
                st.putAll((
                    model: 0, exciterType: 2, amp: 0.18,
                    brightness: 0.58, material: 0.68, inharm: 0.18, position: 0.36,
                    decay: 0.55, body: 0.42, damp: 0.28, drive: 1.10, tone: 0.52,
                    noiseAmt: 0.26, clickAmt: 0.74, excDecay: 0.012, detune: 0.0015,
                    pitchEnvAmt: 0.05, pitchEnvDecay: 0.022
                ));
            }
        );

        st;
    };

    ~plonkTrackStates = Array.fill(~plonkTrackCount, { |i| ~plonkMakeTrackState.(i) });


    // --------------------------------------------------------
    // audio state
    // --------------------------------------------------------
    ~plonkAudioState = (
        outDevice: "", inDevice: "", sampleRate: 48000, numOutChannels: 2, numInChannels: 0
    );

    ~plonkAudioDevices = Array.new;
    ~plonkAudioOutMenu = nil;
    ~plonkAudioInMenu = nil;
    ~plonkAudioStatus = nil;

    ~plonkSyncAudioStateFromServer = {
        ~plonkAudioState[\outDevice] = (s.options.outDevice ? "").asString;
        ~plonkAudioState[\inDevice] = (s.options.inDevice ? "").asString;
        ~plonkAudioState[\sampleRate] = (s.options.sampleRate ? 48000).asInteger;
        ~plonkAudioState[\numOutChannels] = (s.options.numOutputBusChannels ? 2).asInteger;
        ~plonkAudioState[\numInChannels] = (s.options.numInputBusChannels ? 0).asInteger;
    };

    ~plonkRefreshAudioDevices = {
        var devs = ServerOptions.devices;
        if(devs.isNil) { devs = [] };
        ~plonkAudioDevices = devs.asArray.collect(_.asString).sort;
    };

    ~plonkRefreshAudioMenus = {
        var outIdx, inIdx;

        ~plonkSyncAudioStateFromServer.();
        ~plonkRefreshAudioDevices.();

        if(~plonkAudioOutMenu.notNil) {
            ~plonkAudioOutMenu.items_(["Current / unchanged"] ++ ~plonkAudioDevices);
            outIdx = ~plonkAudioDevices.indexOf(~plonkAudioState[\outDevice]);
            if(outIdx.isNil) { outIdx = -1 };
            ~plonkAudioOutMenu.value_(outIdx + 1);
        };

        if(~plonkAudioInMenu.notNil) {
            ~plonkAudioInMenu.items_(["Current / unchanged"] ++ ~plonkAudioDevices);
            inIdx = ~plonkAudioDevices.indexOf(~plonkAudioState[\inDevice]);
            if(inIdx.isNil) { inIdx = -1 };
            ~plonkAudioInMenu.value_(inIdx + 1);
        };

        if(~plonkAudioStatus.notNil) {
            ~plonkAudioStatus.string_(
                "Out: " ++ (~plonkAudioState[\outDevice] ? "default")
                ++ " | In: " ++ (~plonkAudioState[\inDevice] ? "default")
                ++ " | SR: " ++ ~plonkAudioState[\sampleRate].asString
                ++ " | OutCh: " ++ ~plonkAudioState[\numOutChannels].asString
                ++ " | InCh: " ++ ~plonkAudioState[\numInChannels].asString
            );
        };
    };

~plonkRebuildAfterAudioChange = {
    ~plonkDefineSynth.();
    MIDIClient.init;
    MIDIIn.connectAll;

    MIDIdef.noteOn(\plonkV520On, { |vel, note|
        var trackIdx = ~plonkSelectedTrack;
        var args = ~plonkTrackStates[trackIdx].copy;
        args[\freq] = note.midicps;
        args[\velocity] = vel / 127;
        args[\trackIndex] = trackIdx;
        ~plonkTrigger.(args);
    });

    ~plonkRefreshAudioMenus.();
    if(~plonkAudioStatus.notNil) {
        ~plonkAudioStatus.string_("Audio ready.");
    };
};

    ~plonkApplyAudioState = {
        var outName, inName, sr, outCh, inCh;

        outName = (~plonkAudioState[\outDevice] ? "").asString;
        inName = (~plonkAudioState[\inDevice] ? "").asString;
        sr = (~plonkAudioState[\sampleRate] ? 48000).asInteger;
        outCh = (~plonkAudioState[\numOutChannels] ? 2).asInteger.clip(2, 128);
        inCh = (~plonkAudioState[\numInChannels] ? 0).asInteger.clip(0, 128);

        ~plonkSeqStop.();
        ~plonkVoices.do { |entry| entry[\synth].set(\gate, 0) };
        ~plonkVoices.clear;
        MIDIdef.noteOn(\plonkV520On).free;

        s.options.memSize = 262144;
        s.options.sampleRate = sr;
        s.options.numOutputBusChannels = outCh;
        s.options.numInputBusChannels = inCh;
        if(outName != "") { s.options.outDevice = outName };
        if(inName != "") { s.options.inDevice = inName };

        if(~plonkAudioStatus.notNil) {
            ~plonkAudioStatus.string_("Rebooting audio server...");
        };

        Routine({
            s.reboot;
            while { s.serverRunning.not } { 0.2.wait };
            0.3.wait;
            ~plonkRebuildAfterAudioChange.();
        }).play(AppClock);
    };

    ~plonkSyncAudioStateFromServer.();
    ~plonkRefreshAudioDevices.();

    // --------------------------------------------------------
    // voice management
    // --------------------------------------------------------
    ~plonkVoices = List.new;
    ~plonkMaxVoices = 16;

    ~plonkStealVoice = {
        if(~plonkVoices.size >= ~plonkMaxVoices) {
            var oldest = ~plonkVoices.removeAt(0);
            if(oldest.notNil) { oldest[\synth].set(\gate, 0) };
        };
    };

    ~plonkChokeDrum = { |trackIdx|
        ~plonkVoices.do { |entry|
            if((entry[\model] == 3) and: { entry[\track] == trackIdx }) {
                entry[\synth].set(\gate, 0);
            };
        };
        ~plonkVoices = ~plonkVoices.select { |entry|
            (entry[\model] != 3) or: { entry[\track] != trackIdx }
        };
    };

~plonkTriggerWithDef = { |defName, overrides|
    var args, synth, trackIdx, voiceModelTag;

    overrides = overrides ? ();
    args = overrides.copy;

    trackIdx = (args.removeAt(\trackIndex) ? -1).asInteger;
    voiceModelTag = (args.removeAt(\voiceModelTag) ? (args[\model] ? -999)).asInteger;

    if((voiceModelTag == 3) and: { trackIdx >= 0 }) {
        ~plonkChokeDrum.(trackIdx);
    };

    ~plonkStealVoice.();
    synth = Synth(defName, args.asKeyValuePairs);

    ~plonkVoices.add((
        synth: synth,
        model: voiceModelTag,
        track: trackIdx,
        time: Main.elapsedTime
    ));

    synth.onFree({
        { ~plonkVoices = ~plonkVoices.select { |entry| entry[\synth] != synth } }.defer;
    });

    synth;
};

~plonkTrigger = { |overrides|
    ~plonkTriggerWithDef.(\plonkV520, overrides);
};

~plonkTriggerLayer2 = { |overrides|
    var args = (overrides ? ()).copy;
    args[\voiceModelTag] = -1; // prevent drum choke logic from treating synth2 as main model
    ~plonkTriggerWithDef.(\plonkV520Layer2, args);
};


    // --------------------------------------------------------
    // sequencer / patterns / chain
    // --------------------------------------------------------
~plonkLockKeys = [
    \semi, \velocity, \decay, \brightness, \material, \inharm, \position,
    \body, \damp, \drive, \tone, \noiseAmt, \clickAmt, \exciterType,
    \model, \pitchEnvAmt, \pitchEnvDecay, \detune, \spread, \pan,
    \filterMode, \filterCutoff, \filterRes, \filterEnvAmt, \filterEnvDecay,
    \combAmt, \combTime, \combDecay,
    \edgeDrive, \foldAmt, \presence,
    \crushMix, \bitDepth, \downsample
];

    ~makePlonkStep = { |on=0|
        (
            on: on,
            prob: 1.0,
            ratchet: 1,
            micro: 0.0,
            gate: 0.85,
            accent: 0.0,
            length: 1,
            tie: 0,
            condType: 0,
            condA: 1,
            condB: 2,
            layerMode: 0,
            engine2Model: 0,
            engine2Exciter: 0,
            layerLevel: 0.60,
            engine2PitchMode: 0,
            engine2SemiOffset: 0,
            engine2DegreeOffset: 0,
            engine2DegreeOctOffset: 0,
            engine2DecayMul: 1.00,
            engine2NoiseOffset: 0.00,
            engine2ClickOffset: 0.00,
            engine2PanOffset: 0.00,

			synth2PitchEnvAmt: 0.0,
            synth2PitchEnvDecay: 0.03,
            synth2PitchEnvCurve: -6.0,
			synth2Drive: 1.40,
			synth2Color: 0.50,
			synth2Motion: 0.25,
			synth2UnisonVoices: 1,
			synth2UnisonDetune: 0.00,
			synth2UnisonStereo: 0.00,
			synth2UnisonDrift: 0.00,

            locks: (
                semi: 0,
                useDegree: 0,
                degree: 0,
                degreeOct: 0,
                velocity: nil, decay: nil, brightness: nil, material: nil, inharm: nil,
                position: nil, body: nil, damp: nil, drive: nil, tone: nil, noiseAmt: nil,
                clickAmt: nil, exciterType: nil, model: nil, pitchEnvAmt: nil,
                pitchEnvDecay: nil, detune: nil, spread: nil, pan: nil
            )
        )
    };

~makePatternArray = {
    Array.fill(32, { ~makePlonkStep.(0) })
};

    ~plonkTrackPatterns = Array.fill(~plonkTrackCount, {
        Array.fill(4, { ~makePatternArray.() })
    });

    ~plonkSteps = ~plonkTrackPatterns[0][0];

    ~plonkSeq = (
        tempo: 120,
        swing: 0.0,
        steps: 32,
        baseMidi: 48,
        isRunning: false,
        task: nil,
        currentStep: -1,
        activeVariation: 0,
        editVariation: 0,
        fillMode: false,
        fillVariation: 3,
        cycleCount: 1,
        lastStepPlayedByTrack: Array.fill(~plonkTrackCount, { false }),

        chainEnabled: false,
        chainSlots: [
            (var: 0, bars: 1),
            (var: 1, bars: 1),
            (var: 2, bars: 1),
            (var: 3, bars: 1)
        ],
        chainIndex: 0,
        chainBarCount: 1
    );

    ~plonkClock = TempoClock.new((~plonkSeq[\tempo] ? 120) / 60);
    ~plonkClock.permanent_(true);

    ~plonkMutate = (
        enabled: false,
        everyCycles: 4,
        amount: 0.20,
        targetVariation: \active
    );

    ~plonkVariationNames = ["A", "B", "C", "D"];
    ~plonkAltState = Array.fill(~plonkTrackCount, { Array.fill(32, { 0 }) });

~plonkSetSelectedTrack = { |idx|
    idx = idx.clip(0, ~plonkTrackCount - 1);
    ~plonkSelectedTrack = idx;
    ~plonkSteps = ~plonkEditStepsForSelectedTrack.();

    if(~plonkRefreshControls.notNil) { ~plonkRefreshControls.() };
    if(~plonkRefreshPatternUI.notNil) { ~plonkRefreshPatternUI.() };
    if(~plonkRefreshLockEditor.notNil) { ~plonkRefreshLockEditor.() };
};

	~plonkEditStepsForSelectedTrack = {
    ~plonkTrackPatterns[~plonkSelectedTrack][~plonkSeq[\editVariation]]
};

~plonkSetEditVariation = { |idx|
    idx = idx.clip(0, 3);
    ~plonkSeq[\editVariation] = idx;
    ~plonkSteps = ~plonkEditStepsForSelectedTrack.();
};

    ~plonkGetChainVar = {
        var slot = ~plonkSeq[\chainSlots][~plonkSeq[\chainIndex]];
        (slot[\var] ? 0).clip(0, 3)
    };

	~plonkPlaybackStepsForSelectedTrack = {
    ~plonkTrackPatterns[~plonkSelectedTrack][~plonkCurrentPlaybackVariation.()]
};

    ~plonkCurrentPlaybackVariation = {
        if(~plonkSeq[\fillMode]) {
            ~plonkSeq[\fillVariation]
        }{
            if(~plonkSeq[\chainEnabled]) {
                ~plonkGetChainVar.()
            }{
                ~plonkSeq[\activeVariation]
            }
        }
    };

    ~plonkPlaybackStepsForTrack = { |trackIdx|
        ~plonkTrackPatterns[trackIdx.clip(0, ~plonkTrackCount - 1)][~plonkCurrentPlaybackVariation.()]
    };

    ~plonkAdvanceChain = {
        var slot, bars;

        if(~plonkSeq[\chainEnabled].not) {
            nil;
        }{
            slot = ~plonkSeq[\chainSlots][~plonkSeq[\chainIndex]];
            bars = (slot[\bars] ? 1).asInteger.max(1);

            if(~plonkSeq[\chainBarCount] >= bars) {
                ~plonkSeq[\chainIndex] = (~plonkSeq[\chainIndex] + 1) % ~plonkSeq[\chainSlots].size;
                ~plonkSeq[\chainBarCount] = 1;
            }{
                ~plonkSeq[\chainBarCount] = ~plonkSeq[\chainBarCount] + 1;
            };
        };
    };

    ~plonkResetChain = {
        ~plonkSeq[\chainIndex] = 0;
        ~plonkSeq[\chainBarCount] = 1;
    };

    ~plonkFillChainWithEditVariation = {
        var editVar = ~plonkSeq[\editVariation].clip(0, 3);
        ~plonkSeq[\chainSlots].size.do { |i|
            ~plonkSeq[\chainSlots][i][\var] = editVar;
        };
    };

    ~plonkClearCurrentVariation = {
        var trackIdx = ~plonkSelectedTrack;
        var varIdx = ~plonkSeq[\editVariation];

        ~plonkTrackPatterns[trackIdx][varIdx] = Array.fill(32, { ~makePlonkStep.(0) });
        ~plonkSetEditVariation.(varIdx);
    };

    ~plonkRotateCurrentVariation = { |dir=1|
        var trackIdx = ~plonkSelectedTrack;
        var varIdx = ~plonkSeq[\editVariation];
        var src = ~plonkTrackPatterns[trackIdx][varIdx];
        var dst = Array.newClear(32);

        32.do { |i|
            var newIndex = (i + dir) % 32;
            if(newIndex < 0) { newIndex = newIndex + 32 };
            dst[newIndex] = src[i].deepCopy;
        };

        ~plonkTrackPatterns[trackIdx][varIdx] = dst;
        ~plonkSetEditVariation.(varIdx);
    };

    ~plonkCopyStepRangeInCurrentVariation = { |srcStart=0, srcEnd=3, dstStart=8|
        var trackIdx = ~plonkSelectedTrack;
        var varIdx = ~plonkSeq[\editVariation];
        var arr = ~plonkTrackPatterns[trackIdx][varIdx];
        var a = srcStart.asInteger.clip(0, 31);
        var b = srcEnd.asInteger.clip(0, 31);
        var d = dstStart.asInteger.clip(0, 31);
        var len, temp;

        if(b < a) {
            var t = a;
            a = b;
            b = t;
        };

        len = (b - a) + 1;
        temp = Array.fill(len, { |i| arr[a + i].deepCopy });

        len.do { |i|
            var di = d + i;
            if(di <= 31) {
                arr[di] = temp[i].deepCopy;
            };
        };

        ~plonkSetEditVariation.(varIdx);
    };

    ~plonkStepBeatDur = { |stepIndex|
        var baseDur = 1 / 4;
        var swing = ~plonkSeq[\swing].clip(0, 0.49);

        if(stepIndex.odd) {
            baseDur * (1 + swing);
        }{
            baseDur * (1 - swing);
        };
    };

    ~plonkTiedHoldBeats = { |stepIndex, len|
        var total = 0.0;
        var stepsCount = ~plonkSeq[\steps].clip(1, 32);
        var safeLen = len.asInteger.clip(1, 8);

        safeLen.do { |k|
            var idx = (stepIndex + k) % stepsCount;
            total = total + ~plonkStepBeatDur.(idx);
        };

        total;
    };

    ~plonkIsTiedContinuation = { |steps, stepIndex|
        var found = false;

        7.do { |n|
            var offset = n + 1;
            var prevIdx = stepIndex - offset;

            if(prevIdx >= 0) {
                var prev = steps[prevIdx];
                var prevLen = (prev[\length] ? 1).asInteger.max(1);
                var prevTie = (prev[\tie] ? 0).asInteger;

                if(
                    (prev[\on] == 1) and:
                    { prevTie == 1 } and:
                    { prevLen > offset }
                ) {
                    found = true;
                };
            };
        };

        found;
    };

~plonkStepMidiForIndex = { |idx|
    var steps = ~plonkTrackPatterns[~plonkSelectedTrack][~plonkSeq[\editVariation]];
    var locks = steps[idx][\locks];
    var useDegree = (locks[\useDegree] ? 0).asInteger;
    var midi;
    var tonicBase = ~plonkRootAlignedBaseMidi.(~plonkSeq[\baseMidi]);

    if(useDegree == 1) {
        midi = ~plonkDegreeToMidi.(locks[\degree] ? 0, locks[\degreeOct] ? 0);
    }{
        midi = ~plonkQuantizeMidi.((tonicBase + (locks[\semi] ? 0)).clip(0, 127));
    };

    midi.clip(0, 127);
};


 ~plonkBuildStepArgs = { |trackIdx, step|
    var args = ~plonkTrackStates[trackIdx].copy;
    var locks = step[\locks];
    var useDegree = (locks[\useDegree] ? 0).asInteger;
    var noteMidi;
    var accentAmt = step[\accent].clip(0, 1);
    var tonicBase = ~plonkRootAlignedBaseMidi.(~plonkSeq[\baseMidi]);

    if(useDegree == 1) {
        noteMidi = ~plonkDegreeToMidi.(locks[\degree] ? 0, locks[\degreeOct] ? 0);
    }{
        noteMidi = ~plonkQuantizeMidi.(tonicBase + (locks[\semi] ? 0));
    };

    args[\freq] = noteMidi.clip(0, 127).midicps;
    if(locks[\velocity].notNil) { args[\velocity] = locks[\velocity] };

    ~plonkLockKeys.do { |k|
        if((k != \semi) and: { k != \useDegree } and: { k != \degree } and: { k != \degreeOct } and: { locks[k].notNil }) {
            args[k] = locks[k];
        };
    };

    args[\velocity] = (args[\velocity] + (accentAmt * 0.20)).clip(0, 1);
    args[\brightness] = (args[\brightness] + (accentAmt * 0.10)).clip(0, 1);
    args[\clickAmt] = (args[\clickAmt] + (accentAmt * 0.18)).clip(0, 2.0);
    args[\drive] = (args[\drive] + (accentAmt * 0.08)).clip(0.7, 2.0);
    args[\trackIndex] = trackIdx;

    args;
};

~plonkBuildLayer2Args = { |trackIdx, step|
    var mainLocks = step[\locks];
    var useDegree = (mainLocks[\useDegree] ? 0).asInteger;
    var pitchMode = (step[\engine2PitchMode] ? 0).asInteger.clip(0, 2);
    var tonicBase = ~plonkRootAlignedBaseMidi.(~plonkSeq[\baseMidi]);
    var baseArgs = ~plonkBuildStepArgs.(trackIdx, step).copy;
    var mainMidi, layerMidi, excIdx, synthType;
    var inferredColor, inferredMotion, inferredDrive;
    var args = ();

    if(useDegree == 1) {
        mainMidi = ~plonkDegreeToMidi.(mainLocks[\degree] ? 0, mainLocks[\degreeOct] ? 0);
    }{
        mainMidi = ~plonkQuantizeMidi.(tonicBase + (mainLocks[\semi] ? 0));
    };

    layerMidi = mainMidi;

    switch(pitchMode,
        0, {
            layerMidi = mainMidi;
        },
        1, {
            layerMidi = ~plonkQuantizeMidi.(mainMidi + (step[\engine2SemiOffset] ? 0));
        },
        2, {
            if(useDegree == 1) {
                layerMidi = ~plonkDegreeToMidi.(
                    (mainLocks[\degree] ? 0) + (step[\engine2DegreeOffset] ? 0),
                    (mainLocks[\degreeOct] ? 0) + (step[\engine2DegreeOctOffset] ? 0)
                );
            }{
                layerMidi = ~plonkQuantizeMidi.(mainMidi + (step[\engine2SemiOffset] ? 0));
            };
        }
    );

    excIdx = (step[\engine2Exciter] ? 0).asInteger.clip(0, 5);
    synthType = (step[\engine2Model] ? 0).asInteger.clip(0, 3);

    inferredColor = (
        excIdx.linlin(0, 5, 0.15, 0.95)
        + ((step[\engine2NoiseOffset] ? 0.0) * 0.15)
    ).clip(0, 1);

    inferredMotion = (
        ((step[\engine2DecayMul] ? 1.0).linlin(0.2, 3.0, 0.05, 0.95))
        + ((step[\engine2ClickOffset] ? 0.0).abs * 0.20)
    ).clip(0, 1);

    inferredDrive = (
        1.0
        + ((step[\layerLevel] ? 0.60) * 1.5)
        + ((step[\engine2ClickOffset] ? 0.0) * 0.8)
    ).clip(0.6, 6.0);

    args[\freq] = layerMidi.clip(0, 127).midicps;
    args[\amp] = (baseArgs[\amp] * (step[\layerLevel] ? 0.60)).clip(0.001, 1.0);
    args[\pan] = (baseArgs[\pan] + (step[\engine2PanOffset] ? 0.0)).clip(-1.0, 1.0);
    args[\velocity] = baseArgs[\velocity].clip(0, 1);

    args[\decay] = (baseArgs[\decay] * (step[\engine2DecayMul] ? 1.0)).clip(0.02, 2.0);
    args[\synthType] = synthType;

    args[\color] = (step[\synth2Color] ? inferredColor).clip(0, 1);
    args[\motion] = (step[\synth2Motion] ? inferredMotion).clip(0, 1);
    args[\drive] = (step[\synth2Drive] ? inferredDrive).clip(0.6, 6.0);

    args[\noise] = (step[\engine2NoiseOffset] ? 0.0).clip(-1.0, 1.0);
    args[\click] = (step[\engine2ClickOffset] ? 0.0).clip(-1.0, 1.0);

    args[\pwmWidth] = excIdx.linlin(0, 5, 0.18, 0.82).clip(0.05, 0.95);
    args[\fmRatio] = [0.5, 1.0, 2.0, 3.0, 4.0, 6.0].wrapAt(excIdx);
    args[\fmIndex] = (
        0.3
        + ((step[\engine2DecayMul] ? 1.0) * 2.0)
        + ((step[\engine2ClickOffset] ? 0.0).abs * 2.0)
    ).clip(0.1, 8.0);

    args[\formantMorph] = excIdx.linlin(0, 5, 0.0, 1.0).clip(0, 1);
    args[\ringMix] = (0.2 + ((step[\layerLevel] ? 0.60) * 0.7)).clip(0, 1);

    args[\unisonVoices] = (step[\synth2UnisonVoices] ? 1).asInteger.clip(1, 4);
    args[\unisonDetune] = (step[\synth2UnisonDetune] ? 0.0).clip(0.0, 0.5);
    args[\unisonStereo] = (step[\synth2UnisonStereo] ? 0.0).clip(0.0, 1.0);
    args[\unisonDrift] = (step[\synth2UnisonDrift] ? 0.0).clip(0.0, 1.0);

	args[\pitchEnvAmt] = (step[\synth2PitchEnvAmt] ? 0.0);
    args[\pitchEnvDecay] = (step[\synth2PitchEnvDecay] ? 0.03);
    args[\pitchEnvCurve] = (step[\synth2PitchEnvCurve] ? -6.0);


    args[\trackIndex] = trackIdx;
    args;
};

    ~plonkCheckCondition = { |step, prevPlayed=false|
        var t = step[\condType] ? 0;
        var a = (step[\condA] ? 1).asInteger.max(1);
        var b = (step[\condB] ? 2).asInteger.max(1);
        var cyc = ~plonkSeq[\cycleCount].max(1);

        switch(t,
            0, { true },
            1, { (cyc % 2) == 1 },
            2, { (cyc % 2) == 0 },
            3, { ((cyc - 1) % 4) == 0 },
            4, { ((cyc - 2) % 4) == 0 },
            5, { ((cyc - 3) % 4) == 0 },
            6, { (cyc % 4) == 0 },
            7, { ~plonkSeq[\fillMode] },
            8, { cyc == 1 },
            9, { prevPlayed.not },
            10, { prevPlayed },
            11, { ((cyc - a) % b) == 0 },
            { true }
        )
    };

   ~plonkTriggerStepVoices = { |trackIdx, step, gateDurSecs, stepIndex|
    var mode = (step[\layerMode] ? 0).asInteger.clip(0, 3);
    var mainArgs = ~plonkBuildStepArgs.(trackIdx, step);
    var layerArgs = ~plonkBuildLayer2Args.(trackIdx, step);
    var synths = List.new;

    switch(mode,
        0, {
            synths.add(~plonkTrigger.(mainArgs));
        },
        1, {
            synths.add(~plonkTrigger.(mainArgs));
            synths.add(~plonkTriggerLayer2.(layerArgs));
        },
        2, {
            if(~plonkAltState[trackIdx][stepIndex] == 0) {
                synths.add(~plonkTrigger.(mainArgs));
                ~plonkAltState[trackIdx][stepIndex] = 1;
            }{
                synths.add(~plonkTriggerLayer2.(layerArgs));
                ~plonkAltState[trackIdx][stepIndex] = 0;
            };
        },
        3, {
            if(1.0.rand < 0.5) {
                synths.add(~plonkTrigger.(mainArgs));
            }{
                synths.add(~plonkTriggerLayer2.(layerArgs));
            };
        }
    );

    SystemClock.sched(gateDurSecs, {
        synths.do { |sy| sy.set(\gate, 0) };
        nil
    });

    synths;
};

    ~plonkMutateVariation = { |trackIdx, varIdx|
        var steps = ~plonkTrackPatterns[trackIdx][varIdx];
        var amt = ~plonkMutate[\amount].clip(0, 1);

        32.do { |i|
            var st = steps[i];

            if(amt.coin) {
                st[\prob] = (st[\prob] + rrand(-0.12, 0.12) * amt.linlin(0, 1, 0.2, 1.0)).clip(0.15, 1.0);
            };

            if((amt * 0.65).coin) {
                st[\micro] = (st[\micro] + rrand(-0.04, 0.04) * amt.linlin(0, 1, 0.4, 1.2)).clip(-0.49, 0.49);
            };

            if((amt * 0.45).coin) {
                st[\gate] = (st[\gate] + rrand(-0.10, 0.10) * amt.linlin(0, 1, 0.3, 1.0)).clip(0.05, 1.25);
            };

            if((amt * 0.35).coin) {
                st[\accent] = (st[\accent] + rrand(-0.25, 0.25) * amt.linlin(0, 1, 0.3, 1.0)).clip(0, 1);
            };

            if((amt * 0.28).coin) {
                st[\locks][\useDegree] = [0, 0, 1].choose;
            };

            if((amt * 0.25).coin) {
                if((~plonkPitch[\scaleType] ? 0).asInteger == 0) {
                    if((st[\locks][\useDegree] ? 0) == 1) {
                        st[\locks][\degree] = ((st[\locks][\degree] ? 0) + [-2, -1, 1, 2].choose).clip(-14, 14);
                    }{
                        st[\locks][\semi] = ((st[\locks][\semi] ? 0) + [-2, -1, 1, 2].choose).clip(-24, 24);
                    };
                }{
                    st[\locks][\useDegree] = 1;
                    st[\locks][\degree] = ((st[\locks][\degree] ? 0) + [-2, -1, 1, 2].choose).clip(-14, 14);
                    st[\locks][\semi] = 0;
                };
            };

            if((amt * 0.22).coin) {
                st[\ratchet] = [1, 1, 1, 2, 2, 3, 4].choose;
            };

            if((amt * 0.20).coin) {
                st[\on] = [st[\on], 1 - st[\on]].wchoose([0.8, 0.2]);
            };

            if((amt * 0.18).coin) {
                st[\layerMode] = [0, 0, 1, 2, 3].choose;
                st[\engine2Model] = rrand(0, 3);
                st[\engine2Exciter] = rrand(0, 5);
                st[\layerLevel] = rrand(0.35, 0.90);
                st[\engine2PitchMode] = [0, 0, 1, 2].choose;
                st[\engine2SemiOffset] = [-12, -7, -5, 0, 7, 12].choose;
                st[\engine2DegreeOffset] = [-4, -2, 0, 2, 4].choose;
                st[\engine2DegreeOctOffset] = [-1, 0, 0, 0, 1].choose;
                st[\engine2DecayMul] = rrand(0.50, 1.80);
                st[\engine2NoiseOffset] = rrand(-0.30, 0.30);
                st[\engine2ClickOffset] = rrand(-0.40, 0.40);
                st[\engine2PanOffset] = rrand(-0.70, 0.70);

				st[\synth2Drive] = rrand(0.9, 3.8);
				st[\synth2Color] = rrand(0.0, 1.0);
				st[\synth2Motion] = rrand(0.0, 1.0);
				st[\synth2UnisonVoices] = [1, 1, 2, 2, 3, 4].choose;
				st[\synth2UnisonDetune] = rrand(0.0, 0.18);
				st[\synth2UnisonStereo] = rrand(0.0, 0.95);
				st[\synth2UnisonDrift] = rrand(0.0, 0.45);

				st[\synth2PitchEnvAmt] = rrand(-0.35, 0.45);
				st[\synth2PitchEnvDecay] = exprand(0.005, 0.18);
				st[\synth2PitchEnvCurve] = rrand(-8.0, -2.0);


            };

            if((amt * 0.16).coin) {
                st[\condType] = [0, 0, 0, 1, 2, 3, 4, 9, 10, 11].choose;
                if(st[\condType] == 11) {
                    st[\condA] = rrand(1, 4);
                    st[\condB] = [2, 3, 4, 5, 6, 8].choose;
                };
            };

            if((amt * 0.14).coin) {
                st[\length] = [1, 1, 1, 2, 2, 3, 4].choose;
                st[\tie] = [0, 0, 0, 1].choose;
            };
        };
    };

    ~plonkRunMutationIfNeeded = {
        var targetIdx;

        if(~plonkMutate[\enabled].not) {
            nil;
        }{
            if((~plonkSeq[\cycleCount] % (~plonkMutate[\everyCycles].max(1))) != 0) {
                nil;
            }{
                targetIdx = if(~plonkMutate[\targetVariation] == \edit) {
                    ~plonkSeq[\editVariation]
                }{
                    ~plonkCurrentPlaybackVariation.()
                };

                ~plonkTrackCount.do { |trackIdx|
                    ~plonkMutateVariation.(trackIdx, targetIdx);
                };

                AppClock.sched(0, {
                    if(~plonkRefreshPatternUI.notNil) { ~plonkRefreshPatternUI.() };
                    if(~plonkRefreshLockEditor.notNil) { ~plonkRefreshLockEditor.() };
                    if(~plonkRefreshVarButtons.notNil) { ~plonkRefreshVarButtons.() };
                    nil
                });
            };
        };
    };

   ~plonkRefreshPlayhead = {
    if(~plonkStepIndicators.notNil) {
        AppClock.sched(0, {
            var playSteps = ~plonkPlaybackStepsForSelectedTrack.();

            32.do { |i|
                var isActive = (i == ~plonkSeq[\currentStep]);

                if(~plonkStepIndicators[i].notNil) {
                    ~plonkStepIndicators[i].string_(if(isActive) { "▶" } { " " });
                };

                if(~plonkStepButtons.notNil and: { ~plonkStepButtons[i].notNil }) {
                    if(isActive) {
                        ~plonkStepButtons[i].states_([
                            ["-", Color.black, Color(1.0, 0.82, 0.0)],
                            ["●", Color.black, Color(1.0, 0.82, 0.0)]
                        ]);
                    }{
                        ~plonkStepButtons[i].states_([
                            ["-", Color.black, Color.grey(0.85)],
                            ["●", Color.white, Color.black]
                        ]);
                    };

                    ~plonkStepButtons[i].value_(playSteps[i][\on]);
                };
            };
            nil
        });
    };
};

    ~plonkSeqStop = {
        if(~plonkSeq[\task].notNil) {
            ~plonkSeq[\task].stop;
            ~plonkSeq[\task] = nil;
        };
        ~plonkSeq[\isRunning] = false;
        ~plonkSeq[\currentStep] = -1;
        ~plonkRefreshPlayhead.();
    };

    ~plonkPlayLiveStep = { |stepIndex|
        var stepDur = ~plonkStepBeatDur.(stepIndex);

        ~plonkSeq[\currentStep] = stepIndex;
        ~plonkRefreshPlayhead.();

        ~plonkTrackCount.do { |trackIdx|
            var steps = ~plonkPlaybackStepsForTrack.(trackIdx);
            var st = steps[stepIndex];
            var condPass, didPlay = false;
            var isTieContinuation, noteHoldBeats, gateDurBeats, gateDurSecs;
            var useTie, prevPlayed;

            isTieContinuation = ~plonkIsTiedContinuation.(steps, stepIndex);

            if(isTieContinuation) {
                ~plonkSeq[\lastStepPlayedByTrack][trackIdx] = true;
            }{
                prevPlayed = ~plonkSeq[\lastStepPlayedByTrack][trackIdx] ? false;
                condPass = ~plonkCheckCondition.(st, prevPlayed);

                if(st[\on] == 1 and: { condPass } and: { 1.0.rand <= st[\prob] }) {
                    useTie = (st[\tie] ? 0).asInteger;

                    if(useTie == 1) {
                        noteHoldBeats = ~plonkTiedHoldBeats.(stepIndex, st[\length] ? 1);
                        gateDurBeats = (noteHoldBeats * st[\gate].clip(0.85, 1.25)).max(stepDur * 0.9);
                        gateDurSecs = gateDurBeats / ~plonkClock.tempo.max(0.0001);
                        ~plonkTriggerStepVoices.(trackIdx, st, gateDurSecs, stepIndex);
                        didPlay = true;
                    }{
                        gateDurBeats = (stepDur * st[\gate].clip(0.05, 1.25)).max(0.01);
                        gateDurSecs = gateDurBeats / ~plonkClock.tempo.max(0.0001);
                        ~plonkTriggerStepVoices.(trackIdx, st, gateDurSecs, stepIndex);
                        didPlay = true;
                    };
                };

                ~plonkSeq[\lastStepPlayedByTrack][trackIdx] = didPlay;
            };
        };

        stepDur.wait;
    };

    ~plonkSeqStart = {
        ~plonkSeqStop.();
        ~plonkSeq[\isRunning] = true;
        ~plonkSeq[\lastStepPlayedByTrack] = Array.fill(~plonkTrackCount, { false });
        ~plonkResetChain.();
        ~plonkClock.tempo = ~plonkSeq[\tempo] / 60;

        ~plonkSeq[\task] = Task({
            var idx = 0;
            loop {
                ~plonkPlayLiveStep.(idx);
                idx = (idx + 1) % ~plonkSeq[\steps].clip(1, 32);

                if(idx == 0) {
                    ~plonkSeq[\cycleCount] = ~plonkSeq[\cycleCount] + 1;
                    ~plonkAdvanceChain.();
                    ~plonkRunMutationIfNeeded.();

                    AppClock.sched(0, {
                        if(~plonkRefreshPatternUI.notNil) { ~plonkRefreshPatternUI.() };
                        nil
                    });
                };
            };
        }).play(~plonkClock);
    };

    ~plonkRandomizeOnePattern = { |steps|
        32.do { |i|
            var st = steps[i];

            st[\on] = [0, 1].wchoose([0.4, 0.6]);
            st[\prob] = rrand(0.45, 1.0);
            st[\ratchet] = [1, 1, 1, 2, 2, 3, 4].choose;
            st[\micro] = rrand(-0.18, 0.18);
            st[\gate] = rrand(0.35, 1.10);
            st[\accent] = [0.0, 0.0, 0.25, 0.5, 0.75, 1.0].choose;
            st[\length] = [1, 1, 1, 2, 2, 3, 4].choose;
            st[\tie] = [0, 0, 0, 1].choose;
            st[\condType] = [0, 0, 0, 1, 2, 3, 4, 9, 10, 11].choose;
            st[\condA] = rrand(1, 4);
            st[\condB] = [2, 3, 4, 5, 6, 8].choose;
            st[\layerMode] = [0, 0, 1, 2, 3].choose;
            st[\engine2Model] = rrand(0, 3);
            st[\engine2Exciter] = rrand(0, 5);
            st[\layerLevel] = rrand(0.35, 0.90);
            st[\engine2PitchMode] = [0, 0, 1, 2].choose;
            st[\engine2SemiOffset] = [-12, -7, -5, 0, 7, 12].choose;
            st[\engine2DegreeOffset] = [-4, -2, 0, 2, 4].choose;
            st[\engine2DegreeOctOffset] = [-1, 0, 0, 0, 1].choose;
            st[\engine2DecayMul] = rrand(0.50, 1.80);
            st[\engine2NoiseOffset] = rrand(-0.30, 0.30);
            st[\engine2ClickOffset] = rrand(-0.40, 0.40);
            st[\engine2PanOffset] = rrand(-0.70, 0.70);

			st[\synth2Drive] = rrand(0.9, 3.8);
			st[\synth2Color] = rrand(0.0, 1.0);
			st[\synth2Motion] = rrand(0.0, 1.0);
			st[\synth2UnisonVoices] = [1, 1, 2, 2, 3, 4].choose;
			st[\synth2UnisonDetune] = rrand(0.0, 0.18);
			st[\synth2UnisonStereo] = rrand(0.0, 0.95);
			st[\synth2UnisonDrift] = rrand(0.0, 0.45);

			st[\synth2PitchEnvAmt] = rrand(-0.35, 0.45);
            st[\synth2PitchEnvDecay] = exprand(0.005, 0.18);
            st[\synth2PitchEnvCurve] = rrand(-8.0, -2.0);

            if((~plonkPitch[\scaleType] ? 0).asInteger == 0) {
                st[\locks][\useDegree] = [0, 0, 1].choose;
                st[\locks][\degree] = [-2, -1, 0, 1, 2, 3, 4, 5, 6, 7].choose;
                st[\locks][\degreeOct] = [-1, 0, 0, 0, 1].choose;
                st[\locks][\semi] = [0, 0, 0, 3, 5, 7, 10, 12, -12, -5].choose;
            }{
                st[\locks][\useDegree] = 1;
                st[\locks][\degree] = [-2, -1, 0, 1, 2, 3, 4, 5, 6, 7].choose;
                st[\locks][\degreeOct] = [-1, 0, 0, 0, 1].choose;
                st[\locks][\semi] = 0;
            };

            if(0.55.coin) { st[\locks][\velocity] = rrand(0.35, 1.0) } { st[\locks][\velocity] = nil };
            if(0.35.coin) { st[\locks][\brightness] = rrand(0.0, 1.0) } { st[\locks][\brightness] = nil };
            if(0.35.coin) { st[\locks][\inharm] = rrand(0.0, 0.8) } { st[\locks][\inharm] = nil };
            if(0.30.coin) { st[\locks][\decay] = rrand(0.08, 2.5) } { st[\locks][\decay] = nil };
            if(0.25.coin) { st[\locks][\exciterType] = rrand(0, 5) } { st[\locks][\exciterType] = nil };
            if(0.20.coin) { st[\locks][\model] = rrand(0, 3) } { st[\locks][\model] = nil };

			if(0.35.coin) { st[\locks][\filterCutoff] = rrand(0.08, 0.95) } { st[\locks][\filterCutoff] = nil };
			if(0.30.coin) { st[\locks][\filterRes] = rrand(0.05, 0.90) } { st[\locks][\filterRes] = nil };
			if(0.25.coin) { st[\locks][\filterEnvAmt] = rrand(0.0, 2.8) } { st[\locks][\filterEnvAmt] = nil };
			if(0.22.coin) { st[\locks][\filterEnvDecay] = rrand(0.01, 0.45) } { st[\locks][\filterEnvDecay] = nil };

			if(0.20.coin) { st[\locks][\combAmt] = rrand(0.0, 0.55) } { st[\locks][\combAmt] = nil };
			if(0.18.coin) { st[\locks][\combTime] = exprand(0.0009, 0.018) } { st[\locks][\combTime] = nil };
			if(0.16.coin) { st[\locks][\combDecay] = rrand(0.04, 0.75) } { st[\locks][\combDecay] = nil };

			if(0.28.coin) { st[\locks][\edgeDrive] = rrand(0.8, 4.5) } { st[\locks][\edgeDrive] = nil };
			if(0.22.coin) { st[\locks][\foldAmt] = rrand(0.0, 0.45) } { st[\locks][\foldAmt] = nil };
			if(0.20.coin) { st[\locks][\presence] = rrand(-0.2, 0.8) } { st[\locks][\presence] = nil };

			if(0.16.coin) { st[\locks][\crushMix] = rrand(0.0, 0.35) } { st[\locks][\crushMix] = nil };
			if(0.14.coin) { st[\locks][\bitDepth] = rrand(6, 14) } { st[\locks][\bitDepth] = nil };
			if(0.14.coin) { st[\locks][\downsample] = [1, 2, 3, 4, 6, 8, 12].choose } { st[\locks][\downsample] = nil };

			if(0.12.coin) { st[\locks][\filterMode] = [0, 0, 0, 1, 2, 3].choose } { st[\locks][\filterMode] = nil };
        };
    };


	~plonkRandomizeSelectionRange = { |trackIdx, varIdx, startStep=0, endStep=7, mode=\full, amount=1.0|
    var steps, a, b, densityProb;

    trackIdx = trackIdx.clip(0, ~plonkTrackCount - 1);
    varIdx = varIdx.clip(0, 3);
    amount = amount.clip(0.0, 1.0);

    steps = ~plonkTrackPatterns[trackIdx][varIdx];

    a = startStep.asInteger.clip(0, 31);
    b = endStep.asInteger.clip(0, 31);
    if(b < a) {
        var t = a;
        a = b;
        b = t;
    };

    densityProb = amount.linlin(0, 1, 0.20, 0.85);

    (a..b).do { |i|
        var st = steps[i];
        var chooseDegree;

        switch(mode,

\selection, {
    if((amount * 0.95).coin) {
        st[\on] = if(1.0.rand < densityProb) { 1 } { 0 };
    };
},

            \timing, {
                if((amount * 0.85).coin) {
                    st[\ratchet] = [1, 1, 1, 2, 2, 3, 4].choose;
                };
                if((amount * 0.8).coin) {
                    st[\micro] = rrand(-0.18, 0.18);
                };
                if((amount * 0.8).coin) {
                    st[\gate] = rrand(0.35, 1.10);
                };
                if((amount * 0.55).coin) {
                    st[\length] = [1, 1, 1, 2, 2, 3, 4].choose;
                    st[\tie] = [0, 0, 0, 1].choose;
                };
            },

            \pitch, {
                chooseDegree = if((~plonkPitch[\scaleType] ? 0).asInteger == 0) {
                    [0, 0, 1].choose
                }{
                    1
                };

                st[\locks][\useDegree] = chooseDegree;

                if(chooseDegree == 1) {
                    st[\locks][\degree] = [-4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6].choose;
                    st[\locks][\degreeOct] = [-1, 0, 0, 0, 1].choose;
                    st[\locks][\semi] = 0;
                }{
                    st[\locks][\semi] = [-12, -7, -5, -2, 0, 2, 3, 5, 7, 10, 12].choose;
                };
            },

            \accent, {
                if((amount * 0.85).coin) {
                    st[\accent] = [0.0, 0.0, 0.25, 0.5, 0.75, 1.0].choose;
                };
                if((amount * 0.65).coin) {
                    st[\locks][\velocity] = rrand(0.35, 1.0);
                };
            },

            \layer, {
                if((amount * 0.85).coin) {
                    st[\layerMode] = [0, 0, 1, 2, 3].choose;
                    st[\engine2Model] = rrand(0, 3);
                    st[\engine2Exciter] = rrand(0, 5);
                    st[\layerLevel] = rrand(0.35, 0.90);
                    st[\engine2PitchMode] = [0, 0, 1, 2].choose;
                    st[\engine2SemiOffset] = [-12, -7, -5, 0, 7, 12].choose;
                    st[\engine2DegreeOffset] = [-4, -2, 0, 2, 4].choose;
                    st[\engine2DegreeOctOffset] = [-1, 0, 0, 0, 1].choose;
                    st[\engine2DecayMul] = rrand(0.50, 1.80);
                    st[\engine2NoiseOffset] = rrand(-0.30, 0.30);
                    st[\engine2ClickOffset] = rrand(-0.40, 0.40);
                    st[\engine2PanOffset] = rrand(-0.70, 0.70);

					st[\synth2Drive] = rrand(0.9, 3.8);
					st[\synth2Color] = rrand(0.0, 1.0);
					st[\synth2Motion] = rrand(0.0, 1.0);
					st[\synth2UnisonVoices] = [1, 1, 2, 2, 3, 4].choose;
					st[\synth2UnisonDetune] = rrand(0.0, 0.18);
					st[\synth2UnisonStereo] = rrand(0.0, 0.95);
					st[\synth2UnisonDrift] = rrand(0.0, 0.45);

					st[\synth2PitchEnvAmt] = rrand(-0.35, 0.45);
					st[\synth2PitchEnvDecay] = exprand(0.005, 0.18);
					st[\synth2PitchEnvCurve] = rrand(-8.0, -2.0);
                };
            },

            \full, {
                if((amount * 0.95).coin) {
                    st[\on] = if(1.0.rand < densityProb) { 1 } { 0 };
                };
                if((amount * 0.70).coin) {
                    st[\prob] = rrand(0.45, 1.0);
                };
                if((amount * 0.40).coin) {
                    st[\condType] = [0, 0, 0, 1, 2, 3, 4, 9, 10, 11].choose;
                    if(st[\condType] == 11) {
                        st[\condA] = rrand(1, 4);
                        st[\condB] = [2, 3, 4, 5, 6, 8].choose;
                    };
                };

                if((amount * 0.80).coin) {
                    st[\ratchet] = [1, 1, 1, 2, 2, 3, 4].choose;
                };
                if((amount * 0.75).coin) {
                    st[\micro] = rrand(-0.18, 0.18);
                };
                if((amount * 0.75).coin) {
                    st[\gate] = rrand(0.35, 1.10);
                };
                if((amount * 0.45).coin) {
                    st[\length] = [1, 1, 1, 2, 2, 3, 4].choose;
                    st[\tie] = [0, 0, 0, 1].choose;
                };

                chooseDegree = if((~plonkPitch[\scaleType] ? 0).asInteger == 0) {
                    [0, 0, 1].choose
                }{
                    1
                };

                st[\locks][\useDegree] = chooseDegree;
                if(chooseDegree == 1) {
                    st[\locks][\degree] = [-4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6].choose;
                    st[\locks][\degreeOct] = [-1, 0, 0, 0, 1].choose;
                    st[\locks][\semi] = 0;
                }{
                    st[\locks][\semi] = [-12, -7, -5, -2, 0, 2, 3, 5, 7, 10, 12].choose;
                };

                if((amount * 0.70).coin) {
                    st[\accent] = [0.0, 0.0, 0.25, 0.5, 0.75, 1.0].choose;
                };
                if((amount * 0.45).coin) {
                    st[\locks][\velocity] = rrand(0.35, 1.0);
                };

                if((amount * 0.45).coin) {
                    st[\layerMode] = [0, 0, 1, 2, 3].choose;
                    st[\engine2Model] = rrand(0, 3);
                    st[\engine2Exciter] = rrand(0, 5);
                    st[\layerLevel] = rrand(0.35, 0.90);
                    st[\engine2PitchMode] = [0, 0, 1, 2].choose;
                    st[\engine2SemiOffset] = [-12, -7, -5, 0, 7, 12].choose;
                    st[\engine2DegreeOffset] = [-4, -2, 0, 2, 4].choose;
                    st[\engine2DegreeOctOffset] = [-1, 0, 0, 0, 1].choose;
                    st[\engine2DecayMul] = rrand(0.50, 1.80);
                    st[\engine2NoiseOffset] = rrand(-0.30, 0.30);
                    st[\engine2ClickOffset] = rrand(-0.40, 0.40);
                    st[\engine2PanOffset] = rrand(-0.70, 0.70);

					st[\synth2Drive] = rrand(0.9, 3.8);
					st[\synth2Color] = rrand(0.0, 1.0);
					st[\synth2Motion] = rrand(0.0, 1.0);
					st[\synth2UnisonVoices] = [1, 1, 2, 2, 3, 4].choose;
					st[\synth2UnisonDetune] = rrand(0.0, 0.18);
					st[\synth2UnisonStereo] = rrand(0.0, 0.95);
					st[\synth2UnisonDrift] = rrand(0.0, 0.45);

					st[\synth2PitchEnvAmt] = rrand(-0.35, 0.45);
					st[\synth2PitchEnvDecay] = exprand(0.005, 0.18);
					st[\synth2PitchEnvCurve] = rrand(-8.0, -2.0);
                };

					if((amount * 0.45).coin) {
    st[\locks][\filterCutoff] = rrand(0.08, 0.95);
};
if((amount * 0.35).coin) {
    st[\locks][\filterRes] = rrand(0.05, 0.90);
};
if((amount * 0.28).coin) {
    st[\locks][\filterEnvAmt] = rrand(0.0, 2.8);
};
if((amount * 0.24).coin) {
    st[\locks][\filterEnvDecay] = rrand(0.01, 0.45);
};

if((amount * 0.22).coin) {
    st[\locks][\combAmt] = rrand(0.0, 0.55);
};
if((amount * 0.18).coin) {
    st[\locks][\combTime] = exprand(0.0009, 0.018);
};
if((amount * 0.18).coin) {
    st[\locks][\combDecay] = rrand(0.04, 0.75);
};

if((amount * 0.35).coin) {
    st[\locks][\edgeDrive] = rrand(0.8, 4.5);
};
if((amount * 0.24).coin) {
    st[\locks][\foldAmt] = rrand(0.0, 0.45);
};
if((amount * 0.20).coin) {
						st[\locks][\presence] = rrand(-0.2, 0.8);
};

if((amount * 0.18).coin) {
    st[\locks][\crushMix] = rrand(0.0, 0.35);
};
if((amount * 0.15).coin) {
    st[\locks][\bitDepth] = rrand(6, 14);
};
if((amount * 0.15).coin) {
    st[\locks][\downsample] = [1, 2, 3, 4, 6, 8, 12].choose;
};

if((amount * 0.12).coin) {
    st[\locks][\filterMode] = [0, 0, 0, 1, 2, 3].choose;
};
            }
        );
    };
};

~plonkRandomizeCurrentSelection = { |startStep=0, endStep=7, mode=\full, amount=1.0|
    ~plonkRandomizeSelectionRange.(
        ~plonkSelectedTrack,
        ~plonkSeq[\editVariation],
        startStep,
        endStep,
        mode,
        amount
    );
};

~plonkRandomizeCurrentSelectionAndRefresh = { |startStep=0, endStep=7, mode=\full, amount=1.0|
    var wasRunning = ~plonkSeq[\isRunning];
    ~plonkRandomizeCurrentSelection.(startStep, endStep, mode, amount);
    if(wasRunning) { ~plonkSeqStart.() };
    if(~plonkRefreshPatternUI.notNil) { ~plonkRefreshPatternUI.() };
    if(~plonkRefreshLockEditor.notNil) { ~plonkRefreshLockEditor.() };
};

    ~plonkRandomizePattern = {
        ~plonkRandomizeOnePattern.(~plonkTrackPatterns[~plonkSelectedTrack][~plonkSeq[\editVariation]]);
    };

    ~plonkRandomizePatternAndRefresh = {
        var wasRunning = ~plonkSeq[\isRunning];
        ~plonkRandomizePattern.();
        if(wasRunning) { ~plonkSeqStart.() };
    };

    // --------------------------------------------------------
    // save/load
    // --------------------------------------------------------
    ~plonkSavePattern = { |name="pattern1"|
        var path = ~plonkPatternDir +/+ (name ++ ".archive");
        (
            seq: ~plonkSeq.copy.put(\task, nil),
            trackPatterns: ~plonkTrackPatterns.collect { |trackArr|
                trackArr.collect { |arr| arr.collect(_.deepCopy) }
            },
            trackStates: ~plonkTrackStates.collect(_.copy),
            mutate: ~plonkMutate.copy,
            pitch: ~plonkPitch.copy,
            selectedTrack: ~plonkSelectedTrack
        ).writeArchive(path);
        ("Saved pattern: " ++ path).postln;
    };

    ~plonkLoadPattern = { |name="pattern1"|
        var path = ~plonkPatternDir +/+ (name ++ ".archive");
        var obj;
        if(File.exists(path)) {
            obj = Object.readArchive(path);
            ~plonkSeq.putAll(obj[\seq].copy);
            ~plonkSeq[\task] = nil;
            ~plonkTrackPatterns = obj[\trackPatterns].collect { |trackArr|
                trackArr.collect { |arr| arr.collect(_.deepCopy) }
            };
            ~plonkTrackStates = obj[\trackStates].collect(_.copy);
            ~plonkMutate = obj[\mutate].copy;
            if(obj[\pitch].notNil) { ~plonkPitch = obj[\pitch].copy };
            ~plonkSelectedTrack = (obj[\selectedTrack] ? 0).clip(0, ~plonkTrackCount - 1);
            ~plonkSetEditVariation.(~plonkSeq[\editVariation] ? 0);
            ~plonkClock.tempo = ~plonkSeq[\tempo] / 60;
            ("Loaded pattern: " ++ path).postln;
        }{
            ("Pattern not found: " ++ path).warn;
        };
    };

    // --------------------------------------------------------
    // MIDI
    // --------------------------------------------------------
    MIDIClient.init;
    MIDIIn.connectAll;

MIDIdef.noteOn(\plonkV520On, { |vel, note|
    var trackIdx = ~plonkSelectedTrack;
    var args = ~plonkTrackStates[trackIdx].copy;
    args[\freq] = note.midicps;
    args[\velocity] = vel / 127;
    args[\trackIndex] = trackIdx;
    ~plonkTrigger.(args);
});


    // --------------------------------------------------------
    // GUI
    // --------------------------------------------------------
    {
        var win, header, content;
        var uiW = 1500;
        var uiH = 940;
        var pages = IdentityDictionary.new;
        var controls = IdentityDictionary.new;
        var stepButtons = Array.newClear(32);
        var stepIndicators = Array.newClear(32);
        var stepEditButtons = Array.newClear(32);
        var stepLabels = Array.newClear(32);
        var stepNoteMiniLabels = Array.newClear(32);
        var condMiniLabels = Array.newClear(32);
        var patternField, baseMidiLabel, stepNoteLabel, condSummaryLabel, chainSummaryLabel;
        var copiedVariation = nil;
        var lockStep = 0;
        var lockBoxes = IdentityDictionary.new;
        var lockEnableButtons = IdentityDictionary.new;
        var showPage, refreshControls, refreshPatternUI, refreshLockEditor, refreshVarButtons, refreshChainUI;
        var makeButton, makePage, makeSlider, makeMenu, makeBoundedBox;
        var modelNames = ["Bar", "Plate", "Bell", "Drum"];
        var exciterNames = ["Mallet", "HardPick", "Brush", "Scrape", "Burst", "ImpulseCluster"];

        var varButtons = Array.newClear(4);
        var trackButtons = Array.newClear(4);
       var fillButton, mutateEnableButton, copyVarButton, pasteVarButton, dupVarButton, chainEnableButton, allEditChainButton;
		var chainVarMenus = Array.newClear(4);
		var chainBarBoxes = Array.newClear(4);
		var rangeSrcABox, rangeSrcBBox, rangeDstBox;
		var randSelButton, randModeMenu, randAmtBox;
		var rootMenu, scaleMenu, layerModeMenu, eng2ModelMenu, eng2ExcMenu;

        ~plonkStepIndicators = stepIndicators;
        ~plonkStepButtons = stepButtons;

win = Window("Plonk-ish v5.20", Rect(40, 60, 1450, 900));
win.alwaysOnTop_(false);
win.userCanClose_(true);
win.view.background_(Color.white);

uiW = win.view.bounds.width.asInteger;
uiH = win.view.bounds.height.asInteger;

header = View(win, Rect(0, 0, uiW, 64));
content = View(win, Rect(0, 66, uiW, uiH - 66));

header.resize_(2);
content.resize_(5);

header.background_(Color.white);
content.background_(Color.white);

        makeButton = { |parent, bounds, label, action|
            var b = Button(parent, bounds);
            b.states_([[label]]);
            b.action_({ action.value });
            b;
        };

makePage = { |key|
    var v = View(content, Rect(0, 0, content.bounds.width, content.bounds.height));
    v.visible_(false);
    v.resize_(5);
    v.background_(Color.white);
    pages[key] = v;
    v;
};

        makeBoundedBox = { |parent, bounds, init=0, lo=0, hi=1, step=0.01, decimals=2, action|
            var nb = NumberBox(parent, bounds);
            nb.value_(init);
            nb.clipLo_(lo);
            nb.clipHi_(hi);
            nb.step_(step);
            nb.scroll_step_(step);
            nb.decimals_(decimals);
            nb.action_({ |box|
                var val = box.value.clip(lo, hi);
                if(decimals == 0) { val = val.asInteger };
                box.value_(val);
                action.value(box, val);
            });
            nb;
        };

showPage = { |key|
    pages.keysValuesDo { |k, v|
        v.visible_(false);
    };

    if(pages[key].notNil) {
        pages[key].visible_(true);
    };

    if(refreshControls.notNil) { refreshControls.() };
    if(refreshPatternUI.notNil) { refreshPatternUI.() };
    if(refreshLockEditor.notNil) { refreshLockEditor.() };
    if(~plonkRefreshAudioMenus.notNil and: { key == \audio }) { ~plonkRefreshAudioMenus.() };

    content.refresh;
};


		makeSlider = { |parent, x, y, label, key, min=0.0, max=1.0, spec=\lin|
    var st = StaticText(parent, Rect(x, y, 110, 20));
    var sl = Slider(parent, Rect(x + 110, y + 3, 220, 16));
    var nb = NumberBox(parent, Rect(x + 338, y, 70, 20));
    var entry;

    st.string_(label);

    sl.action_({
        var v;
        var state = ~plonkTrackStates[~plonkSelectedTrack];

        if(spec == \exp) {
            v = sl.value.linexp(0, 1, min.max(0.0001), max);
        }{
            v = sl.value.linlin(0, 1, min, max);
        };

        v = v.clip(min, max);
        state[key] = v;
        nb.value_(v);

        if(~plonkRefreshControls.notNil) { ~plonkRefreshControls.() };
    });

    nb.action_({
        var v = nb.value.clip(min, max);
        var norm;
        var state = ~plonkTrackStates[~plonkSelectedTrack];

        if(spec == \exp) {
            norm = v.explin(min.max(0.0001), max, 0, 1);
        }{
            norm = v.linlin(min, max, 0, 1);
        };

        state[key] = v;
        sl.value_(norm.clip(0, 1));

        if(~plonkRefreshControls.notNil) { ~plonkRefreshControls.() };
    });

    entry = (type: \slider, slider: sl, box: nb, min: min, max: max, spec: spec);

    if(controls[key].isNil) {
        controls[key] = List[entry];
    }{
        controls[key].add(entry);
    };
};

makeMenu = { |parent, x, y, label, key, items|
    var st = StaticText(parent, Rect(x, y, 110, 20));
    var pm = PopUpMenu(parent, Rect(x + 110, y, 220, 20));
    var entry;

    st.string_(label);
    pm.items_(items);
    pm.action_({
        ~plonkTrackStates[~plonkSelectedTrack][key] = pm.value;

        if(~plonkRefreshControls.notNil) { ~plonkRefreshControls.() };
    });

    entry = (type: \menu, menu: pm);

    if(controls[key].isNil) {
        controls[key] = List[entry];
    }{
        controls[key].add(entry);
    };
};

refreshControls = {
    var state = ~plonkTrackStates[~plonkSelectedTrack];

    controls.keysValuesDo { |k, controlList|
        var v = state[k];
        var norm;

        controlList.do { |c|
            if(c[\type] == \slider) {
                if(c[\spec] == \exp) {
                    norm = v.explin(c[\min].max(0.0001), c[\max], 0, 1);
                }{
                    norm = v.linlin(c[\min], c[\max], 0, 1);
                };

                c[\slider].value_(norm.clip(0, 1));
                c[\box].value_(v);
            }{
                if(c[\type] == \menu) {
                    c[\menu].value_(v.asInteger);
                };
            };
        };
    };
};

        refreshVarButtons = {
            4.do { |i|
                if(varButtons[i].notNil) {
                    if(i == ~plonkSeq[\editVariation]) {
                        varButtons[i].states_([
                            [~plonkVariationNames[i], Color.white, Color(0.15, 0.45, 0.85)]
                        ]);
                    }{
                        varButtons[i].states_([
                            [~plonkVariationNames[i], Color.black, Color.grey(0.85)]
                        ]);
                    };
                };
            };

            4.do { |i|
                if(trackButtons[i].notNil) {
                    if(i == ~plonkSelectedTrack) {
                        trackButtons[i].states_([
                            [~plonkTrackNames[i], Color.white, Color(0.65, 0.25, 0.15)]
                        ]);
                    }{
                        trackButtons[i].states_([
                            [~plonkTrackNames[i], Color.black, Color.grey(0.85)]
                        ]);
                    };
                };
            };

            if(fillButton.notNil) {
                if(~plonkSeq[\fillMode]) {
                    fillButton.states_([["Fill", Color.white, Color(0.80, 0.35, 0.1)]]);
                    fillButton.value_(1);
                }{
                    fillButton.states_([["Fill", Color.black, Color.grey(0.85)]]);
                    fillButton.value_(0);
                };
            };

            if(mutateEnableButton.notNil) {
                mutateEnableButton.states_([
                    ["Mut Off", Color.black, Color.grey(0.85)],
                    ["Mut On", Color.white, Color(0.20, 0.60, 0.20)]
                ]);
                mutateEnableButton.value_(~plonkMutate[\enabled].asInteger);
            };

            if(chainEnableButton.notNil) {
                chainEnableButton.states_([
                    ["Chain Off", Color.black, Color.grey(0.85)],
                    ["Chain On", Color.white, Color(0.35, 0.35, 0.80)]
                ]);
                chainEnableButton.value_(~plonkSeq[\chainEnabled].asInteger);
            };
        };

        refreshChainUI = {
            4.do { |i|
                var slot = ~plonkSeq[\chainSlots][i];
                if(chainVarMenus[i].notNil) {
                    chainVarMenus[i].value_(slot[\var] ? 0);
                };
                if(chainBarBoxes[i].notNil) {
                    chainBarBoxes[i].value_((slot[\bars] ? 1).asInteger);
                };
            };

            if(chainSummaryLabel.notNil) {
                chainSummaryLabel.string_(
                    "Track: " ++ ~plonkTrackNames[~plonkSelectedTrack]
                    ++ " | Chain Pos: " ++ (~plonkSeq[\chainIndex] + 1).asString
                    ++ " | Bar: " ++ ~plonkSeq[\chainBarCount].asString
                    ++ " | Play Var: " ++ ~plonkVariationNames[~plonkCurrentPlaybackVariation.()]
                );
            };
        };

       refreshPatternUI = {
    var editSteps = ~plonkEditStepsForSelectedTrack.();
    var playSteps = ~plonkPlaybackStepsForSelectedTrack.();

    32.do { |i|
        var stEdit = editSteps[i];
        var stPlay = playSteps[i];
        var isActive = i < ~plonkSeq[\steps];
        var noteName = ~plonkMidiToName.(~plonkStepMidiForIndex.(i));
var layerTag = switch((stEdit[\layerMode] ? 0).asInteger,
    1, {
        switch((stEdit[\engine2PitchMode] ? 0).asInteger,
            1, { "S2:S" },
            2, { "S2:D" },
            { "S2" }
        )
    },
    2, { "ALT" },
    3, { "RND" },
    { "" }
);

        if(stepButtons[i].notNil) {
            stepButtons[i].enabled_(isActive);

            if(i == ~plonkSeq[\currentStep]) {
                stepButtons[i].states_([
                    ["-", Color.black, Color(1.0, 0.82, 0.0)],
                    ["●", Color.black, Color(1.0, 0.82, 0.0)]
                ]);
            }{
                stepButtons[i].states_([
                    ["-", Color.black, Color.grey(0.85)],
                    ["●", Color.white, Color.black]
                ]);
            };

            // show what is CURRENTLY PLAYING, not just what is being edited
            stepButtons[i].value_(stPlay[\on]);
        };

        if(stepEditButtons[i].notNil) {
            stepEditButtons[i].enabled_(isActive);
        };

        if(stepIndicators[i].notNil) {
            stepIndicators[i].string_(if(i == ~plonkSeq[\currentStep]) { "▶" } { " " });
        };

        if(stepLabels[i].notNil) {
            stepLabels[i].string_((i + 1).asString);
        };

        if(stepNoteMiniLabels[i].notNil) {
            stepNoteMiniLabels[i].string_(if(isActive) { noteName } { "-" });
        };

        if(condMiniLabels[i].notNil) {
            condMiniLabels[i].string_(
                if(isActive) {
                    ~plonkCondShortName.(stEdit)
                    ++ if((stEdit[\tie] ? 0) == 1) { " T" } { "" }
                    ++ if(layerTag != "") { " " ++ layerTag } { "" }
                }{
                    "-"
                }
            );
        };
    };

    if(baseMidiLabel.notNil) {
        baseMidiLabel.string_(~plonkMidiToName.(~plonkSeq[\baseMidi]));
    };

    if(rootMenu.notNil) {
        rootMenu.value_(~plonkPitch[\root].asInteger);
    };

    if(scaleMenu.notNil) {
        scaleMenu.value_(~plonkPitch[\scaleType].asInteger);
    };

    if(stepNoteLabel.notNil) {
        stepNoteLabel.string_(
            "Resulting Note: " ++
            ~plonkMidiToName.(~plonkStepMidiForIndex.(lockStep))
        );
    };

    if(condSummaryLabel.notNil) {
        condSummaryLabel.string_(
            "Track: " ++ ~plonkTrackNames[~plonkSelectedTrack]
            ++ " | Edit: " ++ ~plonkVariationNames[~plonkSeq[\editVariation]]
            ++ " | Play: " ++ ~plonkVariationNames[~plonkCurrentPlaybackVariation.()]
            ++ " | Cycle: " ++ ~plonkSeq[\cycleCount].asString
        );
    };

    refreshVarButtons.();
    refreshChainUI.();
};


		refreshLockEditor = {
			var st, locks;

    lockStep = lockStep.clip(0, 31);
    st = ~plonkSteps[lockStep];
    locks = st[\locks];

    if(lockBoxes[\stepNum].notNil) { lockBoxes[\stepNum].value_(lockStep + 1) };
    if(lockBoxes[\prob].notNil) { lockBoxes[\prob].value_(st[\prob]) };
    if(lockBoxes[\ratchet].notNil) { lockBoxes[\ratchet].value_(st[\ratchet]) };
    if(lockBoxes[\micro].notNil) { lockBoxes[\micro].value_(st[\micro]) };
    if(lockBoxes[\gate].notNil) { lockBoxes[\gate].value_(st[\gate]) };
    if(lockBoxes[\accent].notNil) { lockBoxes[\accent].value_(st[\accent]) };
    if(lockBoxes[\length].notNil) { lockBoxes[\length].value_(st[\length] ? 1) };
    if(lockEnableButtons[\tie].notNil) { lockEnableButtons[\tie].value_(st[\tie] ? 0) };
    if(lockBoxes[\condType].notNil) { lockBoxes[\condType].value_(st[\condType] ? 0) };
    if(lockBoxes[\condA].notNil) { lockBoxes[\condA].value_(st[\condA] ? 1) };
    if(lockBoxes[\condB].notNil) { lockBoxes[\condB].value_(st[\condB] ? 2) };
    if(lockEnableButtons[\on].notNil) { lockEnableButtons[\on].value_(st[\on]) };
    if(lockEnableButtons[\useDegree].notNil) { lockEnableButtons[\useDegree].value_(locks[\useDegree] ? 0) };
    if(lockBoxes[\degree].notNil) { lockBoxes[\degree].value_(locks[\degree] ? 0) };
    if(lockBoxes[\degreeOct].notNil) { lockBoxes[\degreeOct].value_(locks[\degreeOct] ? 0) };
    if(lockBoxes[\semi].notNil) { lockBoxes[\semi].value_(locks[\semi] ? 0) };

   if(layerModeMenu.notNil) { layerModeMenu.value_((st[\layerMode] ? 0).asInteger.clip(0, ~plonkLayerModeNames.size - 1)) };
if(eng2ModelMenu.notNil) { eng2ModelMenu.value_((st[\engine2Model] ? 0).asInteger.clip(0, ~plonkSynth2TypeNames.size - 1)) };
if(eng2ExcMenu.notNil) { eng2ExcMenu.value_((st[\engine2Exciter] ? 0).asInteger.clip(0, ~plonkSynth2VariantNames.size - 1)) };
if(lockBoxes[\layerLevel].notNil) { lockBoxes[\layerLevel].value_(st[\layerLevel] ? 0.60) };
if(lockBoxes[\engine2PitchMode].notNil) { lockBoxes[\engine2PitchMode].value_((st[\engine2PitchMode] ? 0).asInteger.clip(0, ~plonkSynth2PitchModeNames.size - 1)) };
    if(lockBoxes[\engine2SemiOffset].notNil) { lockBoxes[\engine2SemiOffset].value_(st[\engine2SemiOffset] ? 0) };
    if(lockBoxes[\engine2DegreeOffset].notNil) { lockBoxes[\engine2DegreeOffset].value_(st[\engine2DegreeOffset] ? 0) };
    if(lockBoxes[\engine2DegreeOctOffset].notNil) { lockBoxes[\engine2DegreeOctOffset].value_(st[\engine2DegreeOctOffset] ? 0) };
    if(lockBoxes[\engine2DecayMul].notNil) { lockBoxes[\engine2DecayMul].value_(st[\engine2DecayMul] ? 1.00) };
    if(lockBoxes[\engine2NoiseOffset].notNil) { lockBoxes[\engine2NoiseOffset].value_(st[\engine2NoiseOffset] ? 0.00) };
    if(lockBoxes[\engine2ClickOffset].notNil) { lockBoxes[\engine2ClickOffset].value_(st[\engine2ClickOffset] ? 0.00) };
    if(lockBoxes[\engine2PanOffset].notNil) { lockBoxes[\engine2PanOffset].value_(st[\engine2PanOffset] ? 0.00) };

    if(lockBoxes[\synth2Drive].notNil) { lockBoxes[\synth2Drive].value_(st[\synth2Drive] ? 1.40) };
    if(lockBoxes[\synth2Color].notNil) { lockBoxes[\synth2Color].value_(st[\synth2Color] ? 0.50) };
    if(lockBoxes[\synth2Motion].notNil) { lockBoxes[\synth2Motion].value_(st[\synth2Motion] ? 0.25) };
    if(lockBoxes[\synth2UnisonVoices].notNil) { lockBoxes[\synth2UnisonVoices].value_(st[\synth2UnisonVoices] ? 1) };
    if(lockBoxes[\synth2UnisonDetune].notNil) { lockBoxes[\synth2UnisonDetune].value_(st[\synth2UnisonDetune] ? 0.00) };
    if(lockBoxes[\synth2UnisonStereo].notNil) { lockBoxes[\synth2UnisonStereo].value_(st[\synth2UnisonStereo] ? 0.00) };
    if(lockBoxes[\synth2UnisonDrift].notNil) { lockBoxes[\synth2UnisonDrift].value_(st[\synth2UnisonDrift] ? 0.00) };


			    if(lockBoxes[\synth2PitchEnvAmt].notNil) { lockBoxes[\synth2PitchEnvAmt].value_(st[\synth2PitchEnvAmt] ? 0.0) };
    if(lockBoxes[\synth2PitchEnvDecay].notNil) { lockBoxes[\synth2PitchEnvDecay].value_(st[\synth2PitchEnvDecay] ? 0.03) };
    if(lockBoxes[\synth2PitchEnvCurve].notNil) { lockBoxes[\synth2PitchEnvCurve].value_(st[\synth2PitchEnvCurve] ? -6.0) };

~plonkLockKeys.do { |k|
    var enKey = (k.asString ++ "_en").asSymbol;
    var v = locks[k];

    if(lockEnableButtons[enKey].notNil) {
        switch(k,
            \semi, {
                lockEnableButtons[enKey].value_(1);
            },
            \useDegree, {
                // handled by its dedicated button above, do nothing here
                nil;
            },
            \degree, {
                // no separate enable state; tied to useDegree
                nil;
            },
            \degreeOct, {
                // no separate enable state; tied to useDegree
                nil;
            },
            {
                lockEnableButtons[enKey].value_(v.notNil.asInteger);
            }
        );
    };

    if(lockBoxes[k].notNil) {
        if(v.notNil) {
            lockBoxes[k].value_(v);
        }{
            if((k != \semi) and: { k != \degree } and: { k != \degreeOct } and: { k != \useDegree }) {
                lockBoxes[k].value_(0);
            };
        };
    };
};

    if(stepNoteLabel.notNil) {
        stepNoteLabel.string_(
            "Resulting Note: " ++
            ~plonkMidiToName.(~plonkStepMidiForIndex.(lockStep))
        );
    };
};

~plonkRefreshControls = refreshControls;
~plonkRefreshPatternUI = refreshPatternUI;
~plonkRefreshLockEditor = refreshLockEditor;
~plonkRefreshVarButtons = refreshVarButtons;

        // header
        makeButton.(header, Rect(10, 16, 70, 28), "Main", { showPage.(\main) });
        makeButton.(header, Rect(90, 16, 70, 28), "Exciter", { showPage.(\exciter) });
        makeButton.(header, Rect(170, 16, 90, 28), "Resonator", { showPage.(\res) });
        makeButton.(header, Rect(270, 16, 100, 28), "Performance", { showPage.(\perf) });
        makeButton.(header, Rect(380, 16, 100, 28), "Pattern", { showPage.(\pattern) });
        makeButton.(header, Rect(490, 16, 80, 28), "Step", { showPage.(\step) });
        makeButton.(header, Rect(580, 16, 80, 28), "Audio", { showPage.(\audio) });

        Button(header, Rect(680, 16, 90, 28))
        .states_([["Trigger", Color.white, Color(0.9, 0.7, 0.0)]])
        .action_({
            var args = ~plonkTrackStates[~plonkSelectedTrack].copy;
            args[\trackIndex] = ~plonkSelectedTrack;
            ~plonkTrigger.(args);
        });

        makeButton.(header, Rect(790, 16, 90, 28), "RandPat", {
            ~plonkRandomizePatternAndRefresh.();
            refreshPatternUI.();
            refreshLockEditor.();
        });

        // main page
        {
            var v = makePage.(\main), y = 20;
            StaticText(v, Rect(20, 0, 500, 20)).string_("Main controls — selected track only");

            makeMenu.(v, 20, y, "Model", \model, modelNames); y = y + 28;
            makeMenu.(v, 20, y, "Exciter", \exciterType, exciterNames); y = y + 28;
            makeSlider.(v, 20, y, "Freq", \freq, 40, 4000, \exp); y = y + 28;
            makeSlider.(v, 20, y, "Amp", \amp, 0.01, 0.6, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Pan", \pan, -1.0, 1.0, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Velocity", \velocity, 0.0, 1.0, \lin); y = y + 28;

            y = y + 20;
            StaticText(v, Rect(20, y, 120, 20)).string_("Pattern Preset");
            patternField = TextField(v, Rect(140, y, 140, 20)).string_("pattern1");
            makeButton.(v, Rect(290, y - 1, 60, 22), "Save", {
                ~plonkSavePattern.(patternField.string);
            });
            makeButton.(v, Rect(356, y - 1, 60, 22), "Load", {
                ~plonkLoadPattern.(patternField.string);
                refreshControls.();
                refreshPatternUI.();
                refreshLockEditor.();
            });
        }.value;

        // exciter page, resonator page, performance page
        // keep same structure as before, but now they operate on selected track
        {
            var v = makePage.(\exciter), y = 20;
            StaticText(v, Rect(20, 0, 500, 20)).string_("Exciter — selected track");
            makeMenu.(v, 20, y, "Exciter", \exciterType, exciterNames); y = y + 28;
            makeSlider.(v, 20, y, "Tone", \tone, 0, 1, \lin); y = y + 28;
            makeSlider.(v, 20, y, "NoiseAmt", \noiseAmt, 0, 1.2, \lin); y = y + 28;
            makeSlider.(v, 20, y, "ClickAmt", \clickAmt, 0, 2.0, \lin); y = y + 28;
            makeSlider.(v, 20, y, "ExcDecay", \excDecay, 0.001, 0.12, \exp); y = y + 28;
        }.value;

        {
            var v = makePage.(\res), y = 20;
            StaticText(v, Rect(20, 0, 500, 20)).string_("Resonator — selected track");
            makeMenu.(v, 20, y, "Model", \model, modelNames); y = y + 28;
            makeSlider.(v, 20, y, "Brightness", \brightness, 0, 1, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Material", \material, 0, 1, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Inharm", \inharm, 0, 0.8, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Position", \position, 0.01, 0.49, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Decay", \decay, 0.03, 6.0, \exp); y = y + 28;
            makeSlider.(v, 20, y, "Body", \body, 0, 1, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Damp", \damp, 0, 1, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Detune", \detune, 0, 0.02, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Spread", \spread, 0.2, 4.5, \lin); y = y + 28;
        }.value;

        {
            var v = makePage.(\perf), y = 20;
            StaticText(v, Rect(20, 0, 500, 20)).string_("Performance — selected track");
            makeSlider.(v, 20, y, "Drive", \drive, 0.7, 2.0, \lin); y = y + 28;
            makeSlider.(v, 20, y, "PitchEnvAmt", \pitchEnvAmt, 0, 0.4, \lin); y = y + 28;
            makeSlider.(v, 20, y, "PitchEnvDec", \pitchEnvDecay, 0.005, 0.12, \exp); y = y + 28;
            makeSlider.(v, 20, y, "Vel->Bright", \velToBright, 0, 0.6, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Vel->Decay", \velToDecay, 0, 0.5, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Vel->Noise", \velToNoise, 0, 0.5, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Vel->Click", \velToClick, 0, 0.5, \lin); y = y + 28;

			makeMenu.(v, 460, 20, "FilterMode", \filterMode, ["LP", "HP", "BP", "Notch"]);
			makeSlider.(v, 460, 48, "FiltCut", \filterCutoff, 0, 1, \lin);
			makeSlider.(v, 460, 76, "FiltRes", \filterRes, 0.01, 0.98, \lin);
			makeSlider.(v, 460, 104, "FiltEnvAmt", \filterEnvAmt, 0, 4, \lin);
			makeSlider.(v, 460, 132, "FiltEnvDec", \filterEnvDecay, 0.005, 1.5, \exp);

			makeSlider.(v, 460, 188, "CombAmt", \combAmt, 0, 1, \lin);
			makeSlider.(v, 460, 216, "CombTime", \combTime, 0.0007, 0.03, \exp);
			makeSlider.(v, 460, 244, "CombDecay", \combDecay, 0.02, 2.0, \exp);

			makeSlider.(v, 460, 300, "EdgeDrive", \edgeDrive, 0.5, 8.0, \exp);
			makeSlider.(v, 460, 328, "FoldAmt", \foldAmt, 0, 1, \lin);
			makeSlider.(v, 460, 356, "Presence", \presence, -1, 1, \lin);

			makeSlider.(v, 460, 412, "CrushMix", \crushMix, 0, 1, \lin);
			makeSlider.(v, 460, 440, "BitDepth", \bitDepth, 2, 16, \lin);
			makeSlider.(v, 460, 468, "Downsample", \downsample, 1, 24, \lin);
        }.value;

        // pattern page
        {
            var v = makePage.(\pattern);
            var leftPad = 20;
            var cellW = 58;
            var trigW = 44;
            var editW = 44;
            var noteW = 44;
            var labelOffset = 10;
            var trigOffset = 0;
            var editOffset = 0;
            var noteOffset = 0;
            var indicatorOffset = 12;
            var gridStartX = leftPad;
            var mutateEveryBox, mutateAmtBox;
            var y1 = 22;
            var y2 = 54;
            var y3 = 86;
            var y4 = 118;
            var topY1 = 172;
            var topY2 = 352;

            StaticText(v, Rect(20, 0, 420, 20)).string_("Pattern + playhead (selected track lane)");
            condSummaryLabel = StaticText(v, Rect(460, 0, 420, 20));
            chainSummaryLabel = StaticText(v, Rect(900, 0, 520, 20));

            StaticText(v, Rect(20, y1, 42, 20)).string_("Tempo");
            makeBoundedBox.(v, Rect(64, y1, 56, 20), ~plonkSeq[\tempo], 20, 300, 1, 0, { |nb, val|
                ~plonkSeq[\tempo] = val.asInteger;
                ~plonkClock.tempo = ~plonkSeq[\tempo] / 60;
            });

            StaticText(v, Rect(130, y1, 42, 20)).string_("Swing");
            makeBoundedBox.(v, Rect(174, y1, 56, 20), ~plonkSeq[\swing], 0, 0.49, 0.01, 2, { |nb, val|
                ~plonkSeq[\swing] = val;
            });

            StaticText(v, Rect(240, y1, 38, 20)).string_("Steps");
            makeBoundedBox.(v, Rect(282, y1, 56, 20), ~plonkSeq[\steps], 1, 32, 1, 0, { |nb, val|
                ~plonkSeq[\steps] = val.asInteger;
                refreshPatternUI.();
            });

            StaticText(v, Rect(350, y1, 34, 20)).string_("Base");
            makeBoundedBox.(v, Rect(386, y1, 56, 20), ~plonkSeq[\baseMidi], 0, 127, 1, 0, { |nb, val|
                ~plonkSeq[\baseMidi] = val.asInteger;
                refreshPatternUI.();
                refreshLockEditor.();
            });

            baseMidiLabel = StaticText(v, Rect(446, y1, 48, 20));
            baseMidiLabel.string_(~plonkMidiToName.(~plonkSeq[\baseMidi]));

            StaticText(v, Rect(500, y1, 30, 20)).string_("Root");
            rootMenu = PopUpMenu(v, Rect(534, y1, 52, 20));
            rootMenu.items_(~plonkNoteNames);
            rootMenu.value_(~plonkPitch[\root].asInteger);
            rootMenu.action_({
                ~plonkPitch[\root] = rootMenu.value.asInteger;
                refreshPatternUI.();
                refreshLockEditor.();
            });

            StaticText(v, Rect(594, y1, 34, 20)).string_("Scale");
            scaleMenu = PopUpMenu(v, Rect(632, y1, 112, 20));
            scaleMenu.items_(~plonkScaleNames);
            scaleMenu.value_(~plonkPitch[\scaleType].asInteger);
            scaleMenu.action_({
                ~plonkPitch[\scaleType] = scaleMenu.value.asInteger;
                refreshPatternUI.();
                refreshLockEditor.();
            });

            Button(v, Rect(760, y1 - 1, 50, 22))
            .states_([["Run", Color.white, Color.green(0.75)]])
            .action_({ ~plonkSeqStart.(); });

            Button(v, Rect(816, y1 - 1, 50, 22))
            .states_([["Stop", Color.white, Color.red(0.8)]])
            .action_({ ~plonkSeqStop.(); });

            StaticText(v, Rect(20, y2, 36, 20)).string_("Track");
            4.do { |i|
                trackButtons[i] = Button(v, Rect(62 + (i * 62), y2 - 1, 58, 22))
                .states_([[~plonkTrackNames[i]]])
                .action_({
                    ~plonkSetSelectedTrack.(i);
                    refreshControls.();
                    refreshPatternUI.();
                    refreshLockEditor.();
                });
            };

            StaticText(v, Rect(330, y2, 58, 20)).string_("Variation");
            4.do { |i|
                varButtons[i] = Button(v, Rect(392 + (i * 32), y2 - 1, 28, 22))
                .states_([[~plonkVariationNames[i]]])
                .action_({
                    ~plonkSeq[\activeVariation] = i;
                    ~plonkSetEditVariation.(i);
                    refreshPatternUI.();
                    refreshLockEditor.();
                });
            };

            fillButton = Button(v, Rect(526, y2 - 1, 40, 22))
            .states_([["Fill"]])
            .action_({
                ~plonkSeq[\fillMode] = fillButton.value == 1;
                refreshVarButtons.();
                refreshPatternUI.();
            });

            copyVarButton = Button(v, Rect(572, y2 - 1, 44, 22))
            .states_([["Copy"]])
            .action_({
                copiedVariation = ~plonkTrackPatterns[~plonkSelectedTrack][~plonkSeq[\editVariation]].collect(_.deepCopy);
            });

            pasteVarButton = Button(v, Rect(620, y2 - 1, 44, 22))
            .states_([["Paste"]])
            .action_({
                if(copiedVariation.notNil) {
                    ~plonkTrackPatterns[~plonkSelectedTrack][~plonkSeq[\editVariation]] = copiedVariation.collect(_.deepCopy);
                    ~plonkSetEditVariation.(~plonkSeq[\editVariation]);
                    refreshPatternUI.();
                    refreshLockEditor.();
                };
            });

            dupVarButton = Button(v, Rect(668, y2 - 1, 56, 22))
            .states_([["Dup->"]])
            .action_({
                var src, dst;
                src = ~plonkSeq[\editVariation];
                dst = (src + 1) % 4;
                ~plonkTrackPatterns[~plonkSelectedTrack][dst] =
                    ~plonkTrackPatterns[~plonkSelectedTrack][src].collect(_.deepCopy);
                refreshPatternUI.();
                refreshLockEditor.();
            });


			StaticText(v, Rect(740, y2, 52, 20)).string_("Mutation");

mutateEnableButton = Button(v, Rect(796, y2 - 1, 64, 22))
.states_([
    ["Mut Off", Color.black, Color.grey(0.85)],
    ["Mut On", Color.white, Color(0.20, 0.60, 0.20)]
])
.action_({ |bt|
    ~plonkMutate[\enabled] = (bt.value == 1);
    refreshVarButtons.();
});

StaticText(v, Rect(872, y2, 22, 20)).string_("Ev");
makeBoundedBox.(v, Rect(896, y2, 42, 20), ~plonkMutate[\everyCycles], 1, 32, 1, 0, { |nb, val|
    ~plonkMutate[\everyCycles] = val.asInteger;
});

StaticText(v, Rect(948, y2, 28, 20)).string_("Amt");
makeBoundedBox.(v, Rect(980, y2, 52, 20), ~plonkMutate[\amount], 0, 1, 0.01, 2, { |nb, val|
    ~plonkMutate[\amount] = val;
});


			StaticText(v, Rect(1042, y2, 40, 20)).string_("Tgt");
PopUpMenu(v, Rect(1084, y2, 72, 20))
.items_(["Active", "Edit"])
.value_(if(~plonkMutate[\targetVariation] == \edit) { 1 } { 0 })
.action_({ |pm|
    ~plonkMutate[\targetVariation] = if(pm.value == 1) { \edit } { \active };
});

            StaticText(v, Rect(20, y3, 40, 20)).string_("Chain");
            chainEnableButton = Button(v, Rect(62, y3 - 1, 68, 22))
            .states_([
                ["Chain Off", Color.black, Color.grey(0.85)],
                ["Chain On", Color.white, Color(0.35, 0.35, 0.80)]
            ])
            .action_({ |bt|
                ~plonkSeq[\chainEnabled] = (bt.value == 1);
                ~plonkResetChain.();
                refreshVarButtons.();
                refreshPatternUI.();
            });

            allEditChainButton = Button(v, Rect(136, y3 - 1, 62, 22))
            .states_([["All=Edit"]])
            .action_({
                ~plonkFillChainWithEditVariation.();
                refreshPatternUI.();
            });

            4.do { |i|
                var x = 212 + (i * 120);
                StaticText(v, Rect(x, y3, 18, 20)).string_(("S" ++ (i + 1).asString));
                chainVarMenus[i] = PopUpMenu(v, Rect(x + 18, y3, 44, 20));
                chainVarMenus[i].items_(~plonkVariationNames);
                chainVarMenus[i].action_({
                    ~plonkSeq[\chainSlots][i][\var] = chainVarMenus[i].value.clip(0, 3);
                    refreshPatternUI.();
                });

                StaticText(v, Rect(x + 68, y3, 24, 20)).string_("Cy");
                chainBarBoxes[i] = makeBoundedBox.(v, Rect(x + 92, y3, 26, 20), (~plonkSeq[\chainSlots][i][\bars] ? 1), 1, 8, 1, 0, { |nb, val|
                    ~plonkSeq[\chainSlots][i][\bars] = val.asInteger.max(1);
                    refreshPatternUI.();
                });
            };

            StaticText(v, Rect(20, y4, 50, 20)).string_("Utils");

            Button(v, Rect(74, y4 - 1, 78, 22))
            .states_([["ClearPat"]])
            .action_({
                ~plonkClearCurrentVariation.();
                refreshPatternUI.();
                refreshLockEditor.();
            });

            Button(v, Rect(158, y4 - 1, 42, 22))
            .states_([["RotL"]])
            .action_({
                ~plonkRotateCurrentVariation.(-1);
                refreshPatternUI.();
                refreshLockEditor.();
            });

            Button(v, Rect(204, y4 - 1, 42, 22))
            .states_([["RotR"]])
            .action_({
                ~plonkRotateCurrentVariation.(1);
                refreshPatternUI.();
                refreshLockEditor.();
            });

            StaticText(v, Rect(260, y4, 74, 20)).string_("CopyRange");
            StaticText(v, Rect(344, y4, 20, 20)).string_("A");
            rangeSrcABox = makeBoundedBox.(v, Rect(364, y4, 42, 20), 1, 1, 32, 1, 0, { |nb, val|
                nb.value_(val.asInteger.clip(1, 32));
            });

            StaticText(v, Rect(430, y4, 20, 20)).string_("B");
            rangeSrcBBox = makeBoundedBox.(v, Rect(450, y4, 42, 20), 4, 1, 32, 1, 0, { |nb, val|
                nb.value_(val.asInteger.clip(1, 32));
            });

            StaticText(v, Rect(516, y4, 30, 20)).string_("Dst");
            rangeDstBox = makeBoundedBox.(v, Rect(546, y4, 42, 20), 9, 1, 32, 1, 0, { |nb, val|
                nb.value_(val.asInteger.clip(1, 32));
            });

Button(v, Rect(625, y4 - 1, 74, 22))
.states_([["CopyRan"]])
.action_({
    ~plonkCopyStepRangeInCurrentVariation.(
        (rangeSrcABox.value.asInteger - 1).clip(0, 31),
        (rangeSrcBBox.value.asInteger - 1).clip(0, 31),
        (rangeDstBox.value.asInteger - 1).clip(0, 31)
    );
    refreshPatternUI.();
    refreshLockEditor.();
});

randSelButton = Button(v, Rect(710, y4 - 1, 68, 22))
.states_([["RandSel"]])
.action_({
    var modeSym = [\full, \selection, \timing, \pitch, \accent, \layer][randModeMenu.value.clip(0, 5)];

    ~plonkRandomizeCurrentSelectionAndRefresh.(
        (rangeSrcABox.value.asInteger - 1).clip(0, 31),
        (rangeSrcBBox.value.asInteger - 1).clip(0, 31),
        modeSym,
        randAmtBox.value
    );
});

randModeMenu = PopUpMenu(v, Rect(786, y4, 112, 20));
randModeMenu.items_(~plonkRandSelModeNames);
randModeMenu.value_(0);

StaticText(v, Rect(908, y4, 30, 20)).string_("Amt");

randAmtBox = makeBoundedBox.(v, Rect(940, y4, 52, 20), 1.0, 0.0, 1.0, 0.01, 2, { |nb, val|
    nb.value_(val);
});


            16.do { |i|
                var x = gridStartX + (i * cellW);

                stepIndicators[i] = StaticText(v, Rect(x + indicatorOffset, topY1, 20, 16));
                stepIndicators[i].string_(" ");

                stepLabels[i] = StaticText(v, Rect(x + labelOffset, topY1 + 18, 34, 16));
                stepLabels[i].string_((i + 1).asString);

                stepButtons[i] = Button(v, Rect(x + trigOffset, topY1 + 40, trigW, 24));
                stepButtons[i].states_([
                    ["-", Color.black, Color.grey(0.85)],
                    ["●", Color.white, Color.black]
                ]);
                stepButtons[i].value_(~plonkSteps[i][\on]);
                stepButtons[i].action_({ |bt| ~plonkSteps[i][\on] = bt.value });

                stepEditButtons[i] = makeButton.(v, Rect(x + editOffset, topY1 + 70, editW, 20), "Edit", {
                    lockStep = i;
                    refreshLockEditor.();
                    showPage.(\step);
                });

                stepNoteMiniLabels[i] = StaticText(v, Rect(x + noteOffset, topY1 + 95, noteW, 14));
                stepNoteMiniLabels[i].string_(~plonkMidiToName.(~plonkStepMidiForIndex.(i)));

                condMiniLabels[i] = StaticText(v, Rect(x + noteOffset, topY1 + 110, noteW, 14));
                condMiniLabels[i].string_(~plonkCondShortName.(~plonkSteps[i]));
            };

            16.do { |j|
                var i = j + 16;
                var x = gridStartX + (j * cellW);

                stepIndicators[i] = StaticText(v, Rect(x + indicatorOffset, topY2, 20, 16));
                stepIndicators[i].string_(" ");

                stepLabels[i] = StaticText(v, Rect(x + labelOffset, topY2 + 18, 34, 16));
                stepLabels[i].string_((i + 1).asString);

                stepButtons[i] = Button(v, Rect(x + trigOffset, topY2 + 40, trigW, 24));
                stepButtons[i].states_([
                    ["-", Color.black, Color.grey(0.85)],
                    ["●", Color.white, Color.black]
                ]);
                stepButtons[i].value_(~plonkSteps[i][\on]);
                stepButtons[i].action_({ |bt| ~plonkSteps[i][\on] = bt.value });

                stepEditButtons[i] = makeButton.(v, Rect(x + editOffset, topY2 + 70, editW, 20), "Edit", {
                    lockStep = i;
                    refreshLockEditor.();
                    showPage.(\step);
                });

                stepNoteMiniLabels[i] = StaticText(v, Rect(x + noteOffset, topY2 + 95, noteW, 14));
                stepNoteMiniLabels[i].string_(~plonkMidiToName.(~plonkStepMidiForIndex.(i)));

                condMiniLabels[i] = StaticText(v, Rect(x + noteOffset, topY2 + 110, noteW, 14));
                condMiniLabels[i].string_(~plonkCondShortName.(~plonkSteps[i]));
            };
        }.value;




// step page
{
    var v = makePage.(\step);
    var rowGap = 27;
    var addLockRow;
    var condMenu;
    var pageTitle;

    var yTitle = 8;
    var yRow1 = 54;
    var yRow2 = 98;

    var ySynthHdr = 146;
    var yRow3 = 176;
    var yRow4 = 218;
    var yRow5 = 260;

    var yLocksHdr = 320;
    var yLocks = 350;
    var yBottom = 700;

    var col1X = 22;
    var col2X = 492;
    var col3X = 962;

    var labelW = 112;
    var toggleW = 48;
    var valueW = 96;
    var valueGap = 10;

    pageTitle = StaticText(v, Rect(20, yTitle, 420, 30));
    pageTitle.string_("Per-step Editor");
    pageTitle.font_(Font.default.boldVariant.size_(18));

    // --------------------------------------------------
    // TIMING + CONDITIONS
    // --------------------------------------------------
    StaticText(v, Rect(20, 32, 260, 20))
    .string_("Timing + Conditions")
    .font_(Font.default.boldVariant.size_(13));

    StaticText(v, Rect(20, yRow1, 80, 20)).string_("Step");
    lockBoxes[\stepNum] = makeBoundedBox.(v, Rect(102, yRow1, 52, 20), 1, 1, 32, 1, 0, { |nb, val|
        lockStep = (val.asInteger - 1).clip(0, 31);
        refreshLockEditor.();
    });

    lockEnableButtons[\on] = Button(v, Rect(174, yRow1 - 2, 64, 24))
    .states_([["Off"], ["On"]])
    .action_({ |bt|
        ~plonkSteps[lockStep][\on] = bt.value;
        refreshPatternUI.();
    });

    StaticText(v, Rect(258, yRow1, 42, 20)).string_("Prob");
    lockBoxes[\prob] = makeBoundedBox.(v, Rect(304, yRow1, 64, 20), 1.0, 0, 1, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\prob] = val;
    });

    StaticText(v, Rect(386, yRow1, 34, 20)).string_("Rat");
    lockBoxes[\ratchet] = makeBoundedBox.(v, Rect(424, yRow1, 64, 20), 1, 1, 4, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\ratchet] = val.asInteger;
    });

    StaticText(v, Rect(506, yRow1, 42, 20)).string_("Micro");
    lockBoxes[\micro] = makeBoundedBox.(v, Rect(552, yRow1, 64, 20), 0.0, -0.49, 0.49, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\micro] = val;
    });

    StaticText(v, Rect(634, yRow1, 38, 20)).string_("Gate");
    lockBoxes[\gate] = makeBoundedBox.(v, Rect(676, yRow1, 64, 20), 0.85, 0.05, 1.25, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\gate] = val;
    });

    StaticText(v, Rect(758, yRow1, 50, 20)).string_("Accent");
    lockBoxes[\accent] = makeBoundedBox.(v, Rect(812, yRow1, 64, 20), 0.0, 0, 1, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\accent] = val;
    });

    StaticText(v, Rect(894, yRow1, 28, 20)).string_("Len");
    lockBoxes[\length] = makeBoundedBox.(v, Rect(926, yRow1, 54, 20), 1, 1, 8, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\length] = val.asInteger.clip(1, 8);
    });

    lockEnableButtons[\tie] = Button(v, Rect(998, yRow1 - 2, 70, 24))
    .states_([["Tie Off"], ["Tie On"]])
    .action_({ |bt|
        ~plonkSteps[lockStep][\tie] = bt.value;
        refreshPatternUI.();
    });

    stepNoteLabel = StaticText(v, Rect(1088, yRow1, 260, 20));
    stepNoteLabel.string_("Resulting Note: " ++ ~plonkMidiToName.(~plonkSeq[\baseMidi]));

    StaticText(v, Rect(20, yRow2, 64, 20)).string_("UseDeg");
    lockEnableButtons[\useDegree] = Button(v, Rect(88, yRow2 - 2, 58, 24))
    .states_([["Off"], ["On"]])
    .action_({ |bt|
        ~plonkSteps[lockStep][\locks][\useDegree] = bt.value;
        refreshPatternUI.();
        refreshLockEditor.();
    });

    StaticText(v, Rect(164, yRow2, 54, 20)).string_("Degree");
    lockBoxes[\degree] = makeBoundedBox.(v, Rect(222, yRow2, 64, 20), 0, -14, 14, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\locks][\degree] = val.asInteger;
        refreshPatternUI.();
        refreshLockEditor.();
    });

    StaticText(v, Rect(300, yRow2, 52, 20)).string_("DegOct");
    lockBoxes[\degreeOct] = makeBoundedBox.(v, Rect(356, yRow2, 54, 20), 0, -3, 3, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\locks][\degreeOct] = val.asInteger;
        refreshPatternUI.();
        refreshLockEditor.();
    });

    StaticText(v, Rect(428, yRow2, 72, 20)).string_("Condition");
    condMenu = PopUpMenu(v, Rect(504, yRow2, 150, 20));
    condMenu.items_(~plonkCondNames);
    condMenu.action_({
        ~plonkSteps[lockStep][\condType] = condMenu.value;
        refreshPatternUI.();
    });
    lockBoxes[\condType] = condMenu;

    StaticText(v, Rect(672, yRow2, 18, 20)).string_("A");
    lockBoxes[\condA] = makeBoundedBox.(v, Rect(694, yRow2, 54, 20), 1, 1, 16, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\condA] = val.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(764, yRow2, 18, 20)).string_("B");
    lockBoxes[\condB] = makeBoundedBox.(v, Rect(786, yRow2, 54, 20), 2, 1, 16, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\condB] = val.asInteger;
        refreshPatternUI.();
    });

    // --------------------------------------------------
    // SYNTH2 PARALLEL ENGINE
    // --------------------------------------------------
    StaticText(v, Rect(20, ySynthHdr, 260, 20))
    .string_("Synth2 Parallel Engine")
    .font_(Font.default.boldVariant.size_(13));

    StaticText(v, Rect(20, yRow3, 40, 20)).string_("Mode");
    layerModeMenu = PopUpMenu(v, Rect(64, yRow3, 110, 20));
    layerModeMenu.items_(~plonkLayerModeNames);
    layerModeMenu.action_({
        ~plonkSteps[lockStep][\layerMode] = layerModeMenu.value.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(192, yRow3, 50, 20)).string_("Synth2");
    eng2ModelMenu = PopUpMenu(v, Rect(246, yRow3, 120, 20));
    eng2ModelMenu.items_(~plonkSynth2TypeNames);
    eng2ModelMenu.action_({
        ~plonkSteps[lockStep][\engine2Model] = eng2ModelMenu.value.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(384, yRow3, 52, 20)).string_("Variant");
    eng2ExcMenu = PopUpMenu(v, Rect(440, yRow3, 116, 20));
    eng2ExcMenu.items_(~plonkSynth2VariantNames);
    eng2ExcMenu.action_({
        ~plonkSteps[lockStep][\engine2Exciter] = eng2ExcMenu.value.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(574, yRow3, 38, 20)).string_("Level");
    lockBoxes[\layerLevel] = makeBoundedBox.(v, Rect(616, yRow3, 60, 20), 0.60, 0.05, 1.0, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\layerLevel] = val;
    });

    StaticText(v, Rect(694, yRow3, 36, 20)).string_("Pitch");
    lockBoxes[\engine2PitchMode] = PopUpMenu(v, Rect(734, yRow3, 92, 20));
    lockBoxes[\engine2PitchMode].items_(~plonkSynth2PitchModeNames);
    lockBoxes[\engine2PitchMode].action_({
        ~plonkSteps[lockStep][\engine2PitchMode] = lockBoxes[\engine2PitchMode].value.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(844, yRow3, 32, 20)).string_("Semi");
    lockBoxes[\engine2SemiOffset] = makeBoundedBox.(v, Rect(880, yRow3, 54, 20), 0, -24, 24, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\engine2SemiOffset] = val.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(950, yRow3, 24, 20)).string_("Deg");
    lockBoxes[\engine2DegreeOffset] = makeBoundedBox.(v, Rect(978, yRow3, 54, 20), 0, -14, 14, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\engine2DegreeOffset] = val.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(1048, yRow3, 24, 20)).string_("Oct");
    lockBoxes[\engine2DegreeOctOffset] = makeBoundedBox.(v, Rect(1076, yRow3, 54, 20), 0, -3, 3, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\engine2DegreeOctOffset] = val.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(20, yRow4, 66, 20)).string_("DecayMul");
    lockBoxes[\engine2DecayMul] = makeBoundedBox.(v, Rect(90, yRow4, 62, 20), 1.00, 0.20, 3.00, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\engine2DecayMul] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(170, yRow4, 58, 20)).string_("Noise/Air");
    lockBoxes[\engine2NoiseOffset] = makeBoundedBox.(v, Rect(232, yRow4, 62, 20), 0.00, -1.2, 1.2, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\engine2NoiseOffset] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(312, yRow4, 52, 20)).string_("Bite/Atk");
    lockBoxes[\engine2ClickOffset] = makeBoundedBox.(v, Rect(368, yRow4, 62, 20), 0.00, -2.0, 2.0, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\engine2ClickOffset] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(448, yRow4, 46, 20)).string_("PanOff");
    lockBoxes[\engine2PanOffset] = makeBoundedBox.(v, Rect(498, yRow4, 62, 20), 0.00, -1.0, 1.0, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\engine2PanOffset] = val;
        refreshPatternUI.();
    });

    // dedicated synth2 controls
    StaticText(v, Rect(20, yRow5, 44, 20)).string_("Drive");
    lockBoxes[\synth2Drive] = makeBoundedBox.(v, Rect(68, yRow5, 64, 20), 1.40, 0.60, 6.00, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\synth2Drive] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(150, yRow5, 42, 20)).string_("Color");
    lockBoxes[\synth2Color] = makeBoundedBox.(v, Rect(196, yRow5, 64, 20), 0.50, 0.00, 1.00, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\synth2Color] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(278, yRow5, 48, 20)).string_("Motion");
    lockBoxes[\synth2Motion] = makeBoundedBox.(v, Rect(330, yRow5, 64, 20), 0.25, 0.00, 1.00, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\synth2Motion] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(418, yRow5, 72, 20)).string_("UniVoice");
    lockBoxes[\synth2UnisonVoices] = makeBoundedBox.(v, Rect(494, yRow5, 54, 20), 1, 1, 4, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\synth2UnisonVoices] = val.asInteger.clip(1, 4);
        refreshPatternUI.();
    });

    StaticText(v, Rect(566, yRow5, 62, 20)).string_("UniDet");
    lockBoxes[\synth2UnisonDetune] = makeBoundedBox.(v, Rect(632, yRow5, 64, 20), 0.00, 0.00, 0.50, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\synth2UnisonDetune] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(714, yRow5, 64, 20)).string_("UniStereo");
    lockBoxes[\synth2UnisonStereo] = makeBoundedBox.(v, Rect(782, yRow5, 64, 20), 0.00, 0.00, 1.00, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\synth2UnisonStereo] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(864, yRow5, 56, 20)).string_("UniDrift");
    lockBoxes[\synth2UnisonDrift] = makeBoundedBox.(v, Rect(924, yRow5, 64, 20), 0.00, 0.00, 1.00, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\synth2UnisonDrift] = val;
        refreshPatternUI.();
    });

	StaticText(v, Rect(580, yRow4, 54, 20)).string_("PitchAmt");
    lockBoxes[\synth2PitchEnvAmt] = makeBoundedBox.(v, Rect(638, yRow4, 64, 20), 0.0, -1.0, 1.0, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\synth2PitchEnvAmt] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(720, yRow4, 58, 20)).string_("PitchDec");
    lockBoxes[\synth2PitchEnvDecay] = makeBoundedBox.(v, Rect(782, yRow4, 64, 20), 0.03, 0.001, 1.5, 0.001, 3, { |nb, val|
        ~plonkSteps[lockStep][\synth2PitchEnvDecay] = val;
        refreshPatternUI.();
    });

    StaticText(v, Rect(864, yRow4, 56, 20)).string_("PitchCrv");
    lockBoxes[\synth2PitchEnvCurve] = makeBoundedBox.(v, Rect(924, yRow4, 64, 20), -6.0, -12.0, 12.0, 0.1, 1, { |nb, val|
        ~plonkSteps[lockStep][\synth2PitchEnvCurve] = val;
        refreshPatternUI.();
    });

    // --------------------------------------------------
    // PER-STEP LOCKS
    // --------------------------------------------------
    StaticText(v, Rect(20, yLocksHdr, 260, 20))
    .string_("Per-step Locks")
    .font_(Font.default.boldVariant.size_(13));

    addLockRow = { |x, y, label, key, min, max, step=0.01, decimals=2, isInt=false|
        var toggleX = x + labelW;
        var valueX = toggleX + toggleW + valueGap;

        StaticText(v, Rect(x, y, labelW, 20)).string_(label);

        lockEnableButtons[(key.asString ++ "_en").asSymbol] = Button(v, Rect(toggleX, y - 2, toggleW, 24))
        .states_([["Off"], ["On"]])
        .action_({ |bt|
            var val;
            if(bt.value == 0) {
                if((key != \semi) and: { key != \useDegree } and: { key != \degree } and: { key != \degreeOct }) {
                    ~plonkSteps[lockStep][\locks][key] = nil;
                };
            }{
                val = lockBoxes[key].value;
                if(isInt) { val = val.asInteger };
                ~plonkSteps[lockStep][\locks][key] = val;
            };
            refreshPatternUI.();
            refreshLockEditor.();
        });

        lockBoxes[key] = makeBoundedBox.(v, Rect(valueX, y, valueW, 20), 0, min, max, step, decimals, { |nb, val|
            var writeVal = val;
            if(isInt) { writeVal = val.asInteger };

            if(
                (key == \semi) or:
                { key == \degree } or:
                { key == \degreeOct } or:
                { lockEnableButtons[(key.asString ++ "_en").asSymbol].value == 1 }
            ) {
                ~plonkSteps[lockStep][\locks][key] = writeVal;
            };

            if((key == \semi) or: { key == \degree } or: { key == \degreeOct }) {
                if(stepNoteLabel.notNil) {
                    stepNoteLabel.string_(
                        "Resulting Note: " ++
                        ~plonkMidiToName.(~plonkStepMidiForIndex.(lockStep))
                    );
                };
            };

            refreshPatternUI.();
        });
    };

    // column 1
    addLockRow.(col1X, yLocks + (0 * rowGap), "Semi", \semi, -36, 36, 1, 0, true);
    addLockRow.(col1X, yLocks + (1 * rowGap), "Velocity", \velocity, 0, 1, 0.01, 2, false);
    addLockRow.(col1X, yLocks + (2 * rowGap), "Decay", \decay, 0.03, 6.0, 0.01, 2, false);
    addLockRow.(col1X, yLocks + (3 * rowGap), "Brightness", \brightness, 0, 1, 0.01, 2, false);
    addLockRow.(col1X, yLocks + (4 * rowGap), "Material", \material, 0, 1, 0.01, 2, false);
    addLockRow.(col1X, yLocks + (5 * rowGap), "Inharm", \inharm, 0, 0.8, 0.01, 2, false);
    addLockRow.(col1X, yLocks + (6 * rowGap), "Position", \position, 0.01, 0.49, 0.01, 2, false);
    addLockRow.(col1X, yLocks + (7 * rowGap), "Body", \body, 0, 1, 0.01, 2, false);
    addLockRow.(col1X, yLocks + (8 * rowGap), "Damp", \damp, 0, 1, 0.01, 2, false);
    addLockRow.(col1X, yLocks + (9 * rowGap), "Drive", \drive, 0.7, 2.0, 0.01, 2, false);

    // column 2
    addLockRow.(col2X, yLocks + (0 * rowGap), "Tone", \tone, 0, 1, 0.01, 2, false);
    addLockRow.(col2X, yLocks + (1 * rowGap), "NoiseAmt", \noiseAmt, 0, 1.2, 0.01, 2, false);
    addLockRow.(col2X, yLocks + (2 * rowGap), "ClickAmt", \clickAmt, 0, 2.0, 0.01, 2, false);
    addLockRow.(col2X, yLocks + (3 * rowGap), "ExciterType", \exciterType, 0, 5, 1, 0, true);
    addLockRow.(col2X, yLocks + (4 * rowGap), "Model", \model, 0, 3, 1, 0, true);
    addLockRow.(col2X, yLocks + (5 * rowGap), "PitchEnvAmt", \pitchEnvAmt, 0, 0.4, 0.01, 2, false);
    addLockRow.(col2X, yLocks + (6 * rowGap), "PitchEnvDec", \pitchEnvDecay, 0.005, 0.12, 0.001, 3, false);
    addLockRow.(col2X, yLocks + (7 * rowGap), "Detune", \detune, 0, 0.02, 0.001, 3, false);
    addLockRow.(col2X, yLocks + (8 * rowGap), "Spread", \spread, 0.2, 4.5, 0.01, 2, false);
    addLockRow.(col2X, yLocks + (9 * rowGap), "Pan", \pan, -1, 1, 0.01, 2, false);

    // column 3
    addLockRow.(col3X, yLocks + (0 * rowGap), "FiltCut", \filterCutoff, 0, 1, 0.01, 2, false);
    addLockRow.(col3X, yLocks + (1 * rowGap), "FiltRes", \filterRes, 0.01, 0.98, 0.01, 2, false);
    addLockRow.(col3X, yLocks + (2 * rowGap), "FiltEnvAmt", \filterEnvAmt, 0, 4, 0.01, 2, false);
    addLockRow.(col3X, yLocks + (3 * rowGap), "FiltEnvDec", \filterEnvDecay, 0.005, 1.5, 0.001, 3, false);
    addLockRow.(col3X, yLocks + (4 * rowGap), "CombAmt", \combAmt, 0, 1, 0.01, 2, false);
    addLockRow.(col3X, yLocks + (5 * rowGap), "CombTime", \combTime, 0.0007, 0.03, 0.0005, 4, false);
    addLockRow.(col3X, yLocks + (6 * rowGap), "CombDecay", \combDecay, 0.02, 2.0, 0.01, 2, false);
    addLockRow.(col3X, yLocks + (7 * rowGap), "EdgeDrive", \edgeDrive, 0.5, 8.0, 0.01, 2, false);
    addLockRow.(col3X, yLocks + (8 * rowGap), "FoldAmt", \foldAmt, 0, 1, 0.01, 2, false);
    addLockRow.(col3X, yLocks + (9 * rowGap), "Presence", \presence, -1, 1, 0.01, 2, false);
    addLockRow.(col3X, yLocks + (10 * rowGap), "CrushMix", \crushMix, 0, 1, 0.01, 2, false);
    addLockRow.(col3X, yLocks + (11 * rowGap), "BitDepth", \bitDepth, 2, 16, 1, 0, true);
    addLockRow.(col3X, yLocks + (12 * rowGap), "Downsample", \downsample, 1, 24, 1, 0, true);
    addLockRow.(col3X, yLocks + (13 * rowGap), "FilterMode", \filterMode, 0, 3, 1, 0, true);

    // --------------------------------------------------
    // bottom actions
    // --------------------------------------------------
    makeButton.(v, Rect(24, yBottom, 96, 26), "Trig Step", {
        var st = ~plonkSteps[lockStep];
        if(st[\on] == 0) { st[\on] = 1 };
        ~plonkTriggerStepVoices.(~plonkSelectedTrack, st, 0.35, lockStep);
        refreshPatternUI.();
    });

    makeButton.(v, Rect(136, yBottom, 96, 26), "Clear", {
        var oldSemi = ~plonkSteps[lockStep][\locks][\semi] ? 0;
        var oldUseDegree = ~plonkSteps[lockStep][\locks][\useDegree] ? 0;
        var oldDegree = ~plonkSteps[lockStep][\locks][\degree] ? 0;
        var oldDegreeOct = ~plonkSteps[lockStep][\locks][\degreeOct] ? 0;
        ~plonkSteps[lockStep] = ~makePlonkStep.(~plonkSteps[lockStep][\on]).deepCopy;
        ~plonkSteps[lockStep][\locks][\semi] = oldSemi;
        ~plonkSteps[lockStep][\locks][\useDegree] = oldUseDegree;
        ~plonkSteps[lockStep][\locks][\degree] = oldDegree;
        ~plonkSteps[lockStep][\locks][\degreeOct] = oldDegreeOct;
        refreshLockEditor.();
        refreshPatternUI.();
    });

    makeButton.(v, Rect(248, yBottom, 96, 26), "Copy", {
        ~copiedPlonkStep = ~plonkSteps[lockStep].deepCopy;
    });

    makeButton.(v, Rect(360, yBottom, 96, 26), "Paste", {
        if(~copiedPlonkStep.notNil) {
            ~plonkSteps[lockStep] = ~copiedPlonkStep.deepCopy;
            refreshPatternUI.();
            refreshLockEditor.();
        };
    });
}.value;


        // audio page
        {
            var v = makePage.(\audio);
            var srBox, outChBox, inChBox;

            StaticText(v, Rect(20, 10, 900, 20)).string_("Audio device setup. Changing device reboots the SC server.");

            StaticText(v, Rect(20, 50, 100, 20)).string_("Output Device");
            ~plonkAudioOutMenu = PopUpMenu(v, Rect(130, 50, 420, 22));
            ~plonkAudioOutMenu.items_(["Current / unchanged"]);
            ~plonkAudioOutMenu.action_({
                var idx = ~plonkAudioOutMenu.value;
                if(idx <= 0) {
                    ~plonkAudioState[\outDevice] = (s.options.outDevice ? "").asString;
                }{
                    ~plonkAudioState[\outDevice] = ~plonkAudioDevices[idx - 1];
                };
            });

            StaticText(v, Rect(20, 84, 100, 20)).string_("Input Device");
            ~plonkAudioInMenu = PopUpMenu(v, Rect(130, 84, 420, 22));
            ~plonkAudioInMenu.items_(["Current / unchanged"]);
            ~plonkAudioInMenu.action_({
                var idx = ~plonkAudioInMenu.value;
                if(idx <= 0) {
                    ~plonkAudioState[\inDevice] = (s.options.inDevice ? "").asString;
                }{
                    ~plonkAudioState[\inDevice] = ~plonkAudioDevices[idx - 1];
                };
            });

            StaticText(v, Rect(20, 130, 100, 20)).string_("Sample Rate");
            srBox = makeBoundedBox.(v, Rect(130, 130, 100, 20), ~plonkAudioState[\sampleRate], 8000, 192000, 1, 0, { |nb, val|
                ~plonkAudioState[\sampleRate] = val.asInteger;
            });

            StaticText(v, Rect(20, 164, 100, 20)).string_("Out Channels");
            outChBox = makeBoundedBox.(v, Rect(130, 164, 100, 20), ~plonkAudioState[\numOutChannels], 2, 128, 1, 0, { |nb, val|
                ~plonkAudioState[\numOutChannels] = val.asInteger;
            });

            StaticText(v, Rect(20, 198, 100, 20)).string_("In Channels");
            inChBox = makeBoundedBox.(v, Rect(130, 198, 100, 20), ~plonkAudioState[\numInChannels], 0, 128, 1, 0, { |nb, val|
                ~plonkAudioState[\numInChannels] = val.asInteger;
            });

            makeButton.(v, Rect(20, 250, 120, 26), "Refresh Devices", { ~plonkRefreshAudioMenus.() });
            makeButton.(v, Rect(150, 250, 120, 26), "Apply / Reboot", { ~plonkApplyAudioState.() });
            makeButton.(v, Rect(280, 250, 120, 26), "Use No Input", {
                ~plonkAudioState[\numInChannels] = 0;
                inChBox.value_(0);
                ~plonkRefreshAudioMenus.();
            });

            ~plonkAudioStatus = StaticText(v, Rect(20, 300, 1200, 20));
            ~plonkAudioStatus.string_("Audio status");

            StaticText(v, Rect(20, 340, 1000, 80)).string_(
                "Tip: if you only need output routing, set In Channels to 0. " ++
                "That helps avoid sample-rate mismatch errors with BlackHole, Aggregate Device, or Multi-Output Device."
            );

            ~plonkRefreshAudioMenus.();
        }.value;

        ~plonkSetSelectedTrack.(0);
		~plonkSetEditVariation.(0);
		refreshControls.();
		refreshPatternUI.();
		refreshLockEditor.();
        ~plonkRefreshAudioMenus.();
        showPage.(\main);

		win.front;

        win.onClose_({
            ~plonkSeqStop.();
            MIDIdef.noteOn(\plonkV520On).free;
            ~plonkVoices.do { |entry| entry[\synth].set(\gate, 0) };
            ~plonkVoices.clear;
        });
    }.defer;

});
)

