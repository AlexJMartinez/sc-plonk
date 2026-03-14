(
// ============================================================
// Plonk-ish v5.12
// - conditional trigs / cycle conditions
// - pattern variations A/B/C/D
// - fill mode
// - mutation engine
// - variation copy / paste / duplicate
// - mini condition labels on pattern page
// - variation chain playback
// - utilities: clear var / rotate left / rotate right / copy range
// - fixed Mut Off / Mut On visual toggle
// - fixed sequencer clocking / routine resume crash
// - scale / pitch quantization
// - tie / step length
// - scale degree sequencing
// - multi-engine / layer mode
// - NEW: per-layer parameter offsets for engine 2
// ============================================================

// ---------- pre-boot server options ----------
s.options.memSize = 2097152;
s.options.numWireBufs = 256;

s.waitForBoot({

    // --------------------------------------------------------
    // paths
    // --------------------------------------------------------
    ~plonkEnsureDir = { |p|
        if(File.exists(p).not) {
            ("mkdir -p " ++ p.quote).unixCmd;
        };
    };

    ~plonkV512SoundDir = Platform.userHomeDir +/+ "PlonkV512_Sounds";
    ~plonkV512PatternDir = Platform.userHomeDir +/+ "PlonkV512_Patterns";

    ~plonkEnsureDir.(~plonkV512SoundDir);
    ~plonkEnsureDir.(~plonkV512PatternDir);

    // --------------------------------------------------------
    // helpers
    // --------------------------------------------------------
    ~plonkMidiToName = { |num|
        var names, octave, note;
        names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
        num = num.asInteger.clip(0, 127);
        note = names.wrapAt(num % 12);
        octave = (num div: 12) - 1;
        note ++ octave.asString;
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

    ~plonkDegreeToMidi = { |degree=0, degreeOct=0|
        var scaleType = (~plonkPitch[\scaleType] ? 0).asInteger.clip(0, ~plonkScaleTable.size - 1);
        var intervals = ~plonkScaleTable[scaleType];
        var deg = degree.asInteger;
        var oct = degreeOct.asInteger;
        var size = intervals.size.max(1);
        var wrappedIndex, extraOct, interval;

        if(scaleType == 0) {
            (~plonkSeq[\baseMidi] + deg + (oct * 12)).clip(0, 127);
        }{
            if(deg >= 0) {
                extraOct = deg div: size;
                wrappedIndex = deg % size;
            }{
                extraOct = ((deg + 1) div: size) - 1;
                wrappedIndex = deg - (extraOct * size);
            };

            interval = intervals.wrapAt(wrappedIndex);
            (~plonkSeq[\baseMidi] + interval + ((oct + extraOct) * 12)).clip(0, 127);
        };
    };

    // --------------------------------------------------------
    // synth definition
    // --------------------------------------------------------
    ~plonkDefineSynth = {
        SynthDef(\plonkV512, {
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
            velToClick=0.2|

            var ampEnv, excEnv, pitchEnv;
            var baseFreq, effBright, effDecay, effNoise, effClick;
            var mallet, hardPick, brush, scrape, burst, impulseCluster, exciter;
            var sigA, sigB, sig, bodySig;
            var numModes = 12;
            var strikeShape, brightScale, lowBoost;
            var modelPartialsA, modelPartialsB;
            var ampShapeA, ampShapeB, ringShapeA, ringShapeB;
            var mkBank, bankA, bankB;

            pitchEnv = EnvGen.kr(
                Env([1 + pitchEnvAmt, 1], [pitchEnvDecay], curve: -6)
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
            sig = LPF.ar(sig, effBright.linexp(0, 1, 2200, 17500));
            sig = HPF.ar(sig, 28);
            sig = LeakDC.ar(sig);
            sig = tanh(sig * (1 + (drive * 0.5)));
            sig = sig * amp * ampEnv;

            Out.ar(out, Pan2.ar(sig, pan));
        }).add;
    };

    ~plonkDefineSynth.();
    "Loaded \\plonkV512".postln;

    // --------------------------------------------------------
    // state
    // --------------------------------------------------------
    ~plonkState = (
        freq: 220, amp: 0.24, pan: 0, velocity: 0.90,
        model: 0, exciterType: 0,
        brightness: 0.65, material: 0.55, inharm: 0.22, position: 0.22,
        decay: 1.2, body: 0.45, damp: 0.25, drive: 1.15, tone: 0.58,
        noiseAmt: 0.32, clickAmt: 0.82, excDecay: 0.025, detune: 0.0025, spread: 1.0,
        pitchEnvAmt: 0.0, pitchEnvDecay: 0.03,
        velToBright: 0.35, velToDecay: 0.20, velToNoise: 0.20, velToClick: 0.20
    );

    ~plonkModelPresets = { |which|
        case
        { which == 0 } {
            ~plonkState.putAll((model: 0, exciterType: 0, brightness: 0.45, material: 0.70, inharm: 0.15, position: 0.19,
                decay: 1.2, body: 0.42, damp: 0.30, drive: 1.05, tone: 0.52,
                noiseAmt: 0.14, clickAmt: 0.86, excDecay: 0.020, detune: 0.0016, spread: 1.1,
                pitchEnvAmt: 0.0, pitchEnvDecay: 0.03));
        }
        { which == 1 } {
            ~plonkState.putAll((model: 1, exciterType: 4, brightness: 0.76, material: 0.82, inharm: 0.28, position: 0.27,
                decay: 1.8, body: 0.34, damp: 0.22, drive: 1.12, tone: 0.72,
                noiseAmt: 0.26, clickAmt: 0.66, excDecay: 0.028, detune: 0.0025, spread: 1.0,
                pitchEnvAmt: 0.0, pitchEnvDecay: 0.03));
        }
        { which == 2 } {
            ~plonkState.putAll((model: 2, exciterType: 1, brightness: 0.94, material: 0.96, inharm: 0.40, position: 0.31,
                decay: 2.5, body: 0.20, damp: 0.14, drive: 1.08, tone: 0.82,
                noiseAmt: 0.06, clickAmt: 0.92, excDecay: 0.017, detune: 0.0018, spread: 1.0,
                pitchEnvAmt: 0.0, pitchEnvDecay: 0.03));
        }
        { which == 3 } {
            ~plonkState.putAll((model: 3, exciterType: 2, brightness: 0.30, material: 0.48, inharm: 0.09, position: 0.22,
                decay: 0.8, body: 0.78, damp: 0.36, drive: 1.22, tone: 0.44,
                noiseAmt: 0.46, clickAmt: 0.58, excDecay: 0.030, detune: 0.0036, spread: 1.2,
                pitchEnvAmt: 0.12, pitchEnvDecay: 0.035));
        };
    };

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

        MIDIdef.noteOn(\plonkV512On, { |vel, note|
            ~plonkTrigger.((freq: note.midicps, velocity: vel / 127));
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
        MIDIdef.noteOn(\plonkV512On).free;

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

    ~plonkChokeDrum = {
        ~plonkVoices.do { |entry|
            if(entry[\model] == 3) { entry[\synth].set(\gate, 0) };
        };
        ~plonkVoices = ~plonkVoices.select { |entry| entry[\model] != 3 };
    };

    ~plonkTrigger = { |overrides|
        var args, synth;
        overrides = overrides ? ();
        args = ~plonkState.copy.putAll(overrides);

        if(args[\model] == 3) { ~plonkChokeDrum.() };

        ~plonkStealVoice.();
        synth = Synth(\plonkV512, args.asKeyValuePairs);
        ~plonkVoices.add((synth: synth, model: args[\model], time: Main.elapsedTime));

        synth.onFree({
            { ~plonkVoices = ~plonkVoices.select { |entry| entry[\synth] != synth } }.defer;
        });

        synth;
    };

    // --------------------------------------------------------
    // sequencer / patterns / chain
    // --------------------------------------------------------
    ~plonkLockKeys = [
        \semi, \velocity, \decay, \brightness, \material, \inharm, \position,
        \body, \damp, \drive, \tone, \noiseAmt, \clickAmt, \exciterType,
        \model, \pitchEnvAmt, \pitchEnvDecay, \detune, \spread, \pan,
        \useDegree, \degree, \degreeOct
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
            engine2Model: 3,
            engine2Exciter: 2,
            layerLevel: 0.60,
			engine2PitchMode: 0,
			engine2SemiOffset: 0,
			engine2DegreeOffset: 0,
			engine2DegreeOctOffset: 0,
			engine2DecayMul: 1.00,
			engine2NoiseOffset: 0.00,
			engine2ClickOffset: 0.00,
			engine2PanOffset: 0.00,
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
        Array.fill(32, { |i| ~makePlonkStep.(if(i % 4 == 0) { 1 } { 0 }) })
    };

    ~plonkPatterns = Array.fill(4, { ~makePatternArray.() });
    ~plonkSteps = ~plonkPatterns[0];

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
        lastStepPlayed: false,

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
    ~plonkAltState = Array.fill(32, { 0 });

    ~plonkSetEditVariation = { |idx|
        idx = idx.clip(0, 3);
        ~plonkSeq[\editVariation] = idx;
        ~plonkSteps = ~plonkPatterns[idx];
    };

    ~plonkGetChainVar = {
        var slot = ~plonkSeq[\chainSlots][~plonkSeq[\chainIndex]];
        (slot[\var] ? 0).clip(0, 3)
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

    ~plonkPlaybackSteps = {
        ~plonkPatterns[~plonkCurrentPlaybackVariation.()]
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
        var idx = ~plonkSeq[\editVariation].clip(0, 3);
        ~plonkPatterns[idx] = ~makePatternArray.();
        32.do { |i|
            ~plonkPatterns[idx][i][\on] = 0;
            ~plonkPatterns[idx][i][\locks][\semi] = 0;
            ~plonkPatterns[idx][i][\locks][\useDegree] = 0;
            ~plonkPatterns[idx][i][\locks][\degree] = 0;
            ~plonkPatterns[idx][i][\locks][\degreeOct] = 0;
            ~plonkPatterns[idx][i][\length] = 1;
            ~plonkPatterns[idx][i][\tie] = 0;
            ~plonkPatterns[idx][i][\layerMode] = 0;
            ~plonkPatterns[idx][i][\engine2Model] = 3;
            ~plonkPatterns[idx][i][\engine2Exciter] = 2;
            ~plonkPatterns[idx][i][\layerLevel] = 0.60;
			~plonkPatterns[idx][i][\engine2PitchMode] = 0;
			~plonkPatterns[idx][i][\engine2SemiOffset] = 0;
			~plonkPatterns[idx][i][\engine2DegreeOffset] = 0;
			~plonkPatterns[idx][i][\engine2DegreeOctOffset] = 0;
			~plonkPatterns[idx][i][\engine2DecayMul] = 1.00;
			~plonkPatterns[idx][i][\engine2NoiseOffset] = 0.00;
			~plonkPatterns[idx][i][\engine2ClickOffset] = 0.00;
			~plonkPatterns[idx][i][\engine2PanOffset] = 0.00;
        };
        ~plonkSetEditVariation.(idx);
    };

    ~plonkRotateCurrentVariation = { |dir=1|
        var idx = ~plonkSeq[\editVariation].clip(0, 3);
        var src = ~plonkPatterns[idx];
        var dst = Array.newClear(32);

        32.do { |i|
            var newIndex = (i + dir) % 32;
            if(newIndex < 0) { newIndex = newIndex + 32 };
            dst[newIndex] = src[i].deepCopy;
        };

        ~plonkPatterns[idx] = dst;
        ~plonkSetEditVariation.(idx);
    };

    ~plonkCopyStepRangeInCurrentVariation = { |srcStart=0, srcEnd=3, dstStart=8|
        var idx = ~plonkSeq[\editVariation].clip(0, 3);
        var arr = ~plonkPatterns[idx];
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

        ~plonkSetEditVariation.(idx);
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

    ~plonkIsTiedContinuation = { |stepIndex|
        var steps = ~plonkPlaybackSteps.();
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
        var locks = ~plonkSteps[idx][\locks];
        var useDegree = (locks[\useDegree] ? 0).asInteger;
        var midi;

        if(useDegree == 1) {
            midi = ~plonkDegreeToMidi.(locks[\degree] ? 0, locks[\degreeOct] ? 0);
        }{
            midi = ~plonkQuantizeMidi.((~plonkSeq[\baseMidi] + (locks[\semi] ? 0)).clip(0, 127));
        };

        midi.clip(0, 127);
    };

    ~plonkBuildStepArgs = { |step|
        var args = ~plonkState.copy;
        var locks = step[\locks];
        var useDegree = (locks[\useDegree] ? 0).asInteger;
        var noteMidi;
        var accentAmt = step[\accent].clip(0, 1);

        if(useDegree == 1) {
            noteMidi = ~plonkDegreeToMidi.(locks[\degree] ? 0, locks[\degreeOct] ? 0);
        }{
            noteMidi = ~plonkQuantizeMidi.(~plonkSeq[\baseMidi] + (locks[\semi] ? 0));
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

        args;
    };

~plonkBuildLayer2Args = { |step|
    var args = ~plonkBuildStepArgs.(step).copy;
    var mainLocks = step[\locks];
    var useDegree = (mainLocks[\useDegree] ? 0).asInteger;
    var pitchMode = (step[\engine2PitchMode] ? 0).asInteger.clip(0, 2);
    var mainMidi, layerMidi;

    if(useDegree == 1) {
        mainMidi = ~plonkDegreeToMidi.(mainLocks[\degree] ? 0, mainLocks[\degreeOct] ? 0);
    }{
        mainMidi = ~plonkQuantizeMidi.(~plonkSeq[\baseMidi] + (mainLocks[\semi] ? 0));
    };

    layerMidi = mainMidi;

    switch(pitchMode,
        0, { // follow main pitch exactly
            layerMidi = mainMidi;
        },
        1, { // chromatic/semitone offset
            layerMidi = ~plonkQuantizeMidi.(mainMidi + (step[\engine2SemiOffset] ? 0));
        },
        2, { // degree offset relative to the main degree idea
            if(useDegree == 1) {
                layerMidi = ~plonkDegreeToMidi.(
                    (mainLocks[\degree] ? 0) + (step[\engine2DegreeOffset] ? 0),
                    (mainLocks[\degreeOct] ? 0) + (step[\engine2DegreeOctOffset] ? 0)
                );
            }{
                // if main step is not using degree mode, fall back to quantized semitone movement
                layerMidi = ~plonkQuantizeMidi.(mainMidi + (step[\engine2SemiOffset] ? 0));
            };
        }
    );

    args[\freq] = layerMidi.clip(0, 127).midicps;
    args[\model] = (step[\engine2Model] ? 3).asInteger.clip(0, 3);
    args[\exciterType] = (step[\engine2Exciter] ? 2).asInteger.clip(0, 5);
    args[\amp] = (args[\amp] * (step[\layerLevel] ? 0.60)).clip(0.001, 1.0);
    args[\decay] = (args[\decay] * (step[\engine2DecayMul] ? 1.0)).clip(0.03, 6.0);
    args[\noiseAmt] = (args[\noiseAmt] + (step[\engine2NoiseOffset] ? 0.0)).clip(0.0, 1.2);
    args[\clickAmt] = (args[\clickAmt] + (step[\engine2ClickOffset] ? 0.0)).clip(0.0, 2.0);
    args[\pan] = (args[\pan] + (step[\engine2PanOffset] ? 0.0)).clip(-1.0, 1.0);

    args;
};

    ~plonkCheckCondition = { |step|
        var t = step[\condType] ? 0;
        var a = (step[\condA] ? 1).asInteger.max(1);
        var b = (step[\condB] ? 2).asInteger.max(1);
        var cyc = ~plonkSeq[\cycleCount].max(1);
        var prev = ~plonkSeq[\lastStepPlayed] ? false;

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
            9, { prev.not },
            10, { prev },
            11, { ((cyc - a) % b) == 0 },
            { true }
        )
    };

    ~plonkTriggerStepVoices = { |step, gateDurSecs, stepIndex|
        var mode = (step[\layerMode] ? 0).asInteger.clip(0, 3);
        var mainArgs = ~plonkBuildStepArgs.(step);
        var layerArgs = ~plonkBuildLayer2Args.(step);
        var synths = List.new;

        switch(mode,
            0, {
                synths.add(~plonkTrigger.(mainArgs));
            },
            1, {
                synths.add(~plonkTrigger.(mainArgs));
                synths.add(~plonkTrigger.(layerArgs));
            },
            2, {
                if(~plonkAltState[stepIndex] == 0) {
                    synths.add(~plonkTrigger.(mainArgs));
                    ~plonkAltState[stepIndex] = 1;
                }{
                    synths.add(~plonkTrigger.(layerArgs));
                    ~plonkAltState[stepIndex] = 0;
                };
            },
            3, {
                if(1.0.rand < 0.5) {
                    synths.add(~plonkTrigger.(mainArgs));
                }{
                    synths.add(~plonkTrigger.(layerArgs));
                };
            }
        );

        SystemClock.sched(gateDurSecs, {
            synths.do { |sy|
                sy.set(\gate, 0);
            };
            nil
        });

        synths;
    };

    ~plonkMutateVariation = { |varIdx|
        var steps = ~plonkPatterns[varIdx];
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
                if((st[\locks][\useDegree] ? 0) == 1) {
                    st[\locks][\degree] = ((st[\locks][\degree] ? 0) + [-2, -1, 1, 2].choose).clip(-14, 14);
                }{
                    st[\locks][\semi] = ((st[\locks][\semi] ? 0) + [-2, -1, 1, 2].choose).clip(-24, 24);
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
				st[\engine2PitchMode] = [0, 0, 1, 2].choose;   // 0=follow main, 1=semi offset, 2=degree offset
				st[\engine2SemiOffset] = [-12, -7, -5, 0, 7, 12].choose;
				st[\engine2DegreeOffset] = [-4, -2, 0, 2, 4].choose;
				st[\engine2DegreeOctOffset] = [-1, 0, 0, 0, 1].choose;
				st[\engine2DecayMul] = rrand(0.50, 1.80);
				st[\engine2NoiseOffset] = rrand(-0.30, 0.30);
				st[\engine2ClickOffset] = rrand(-0.40, 0.40);
				st[\engine2PanOffset] = rrand(-0.70, 0.70);
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

                ~plonkMutateVariation.(targetIdx);

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
                32.do { |i|
                    var isActive = (i == ~plonkSeq[\currentStep]);

                    if(~plonkStepIndicators[i].notNil) {
                        if(isActive) {
                            ~plonkStepIndicators[i].string_("▶");
                        }{
                            ~plonkStepIndicators[i].string_(" ");
                        };
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

                        ~plonkStepButtons[i].value_(~plonkSteps[i][\on]);
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
        var steps, st, stepDur, microOffset, ratchetDur, condPass, didPlay = false;
        var isTieContinuation, noteHoldBeats, gateDurBeats, gateDurSecs;
        var useTie;

        steps = ~plonkPlaybackSteps.();
        st = steps[stepIndex];
        stepDur = ~plonkStepBeatDur.(stepIndex);

        ~plonkSeq[\currentStep] = stepIndex;
        ~plonkRefreshPlayhead.();

        isTieContinuation = ~plonkIsTiedContinuation.(stepIndex);

        if(isTieContinuation) {
            didPlay = true;
            stepDur.wait;
        }{
            condPass = ~plonkCheckCondition.(st);

            if(st[\on] == 1 and: { condPass } and: { 1.0.rand <= st[\prob] }) {
                microOffset = st[\micro].clip(-0.49, 0.49) * (stepDur * 0.5);
                ratchetDur = stepDur / st[\ratchet].clip(1, 4);
                useTie = (st[\tie] ? 0).asInteger;

                if(microOffset > 0) { microOffset.wait };

                if(useTie == 1) {
                    noteHoldBeats = ~plonkTiedHoldBeats.(stepIndex, st[\length] ? 1);
                    gateDurBeats = (noteHoldBeats * st[\gate].clip(0.85, 1.25)).max(stepDur * 0.9);
                    gateDurSecs = gateDurBeats / ~plonkClock.tempo.max(0.0001);

                    ~plonkTriggerStepVoices.(st, gateDurSecs, stepIndex);
                    didPlay = true;

                    if(microOffset < 0) {
                        (stepDur + microOffset.abs).wait;
                    }{
                        (stepDur - microOffset).max(0.001).wait;
                    };
                }{
                    st[\ratchet].clip(1, 4).do { |i|
                        gateDurBeats = (ratchetDur * st[\gate].clip(0.05, 1.25)).max(0.01);
                        gateDurSecs = gateDurBeats / ~plonkClock.tempo.max(0.0001);

                        ~plonkTriggerStepVoices.(st, gateDurSecs, stepIndex);
                        didPlay = true;

                        if(i < (st[\ratchet].clip(1, 4) - 1)) {
                            ratchetDur.wait;
                        };
                    };

                    if(microOffset < 0) {
                        (stepDur + microOffset.abs).wait;
                    }{
                        (stepDur - microOffset).max(0.001).wait;
                    };
                };
            }{
                stepDur.wait;
            };
        };

        ~plonkSeq[\lastStepPlayed] = didPlay;
    };

    ~plonkSeqStart = {
        ~plonkSeqStop.();
        ~plonkSeq[\isRunning] = true;
        ~plonkSeq[\lastStepPlayed] = false;
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
            st[\engine2DecayMul] = rrand(0.50, 1.80);
            st[\engine2NoiseOffset] = rrand(-0.30, 0.30);
            st[\engine2ClickOffset] = rrand(-0.40, 0.40);
            st[\engine2PanOffset] = rrand(-0.70, 0.70);

            st[\locks][\useDegree] = [0, 0, 1].choose;
            st[\locks][\degree] = [-2, -1, 0, 1, 2, 3, 4, 5, 6, 7].choose;
            st[\locks][\degreeOct] = [-1, 0, 0, 0, 1].choose;
            st[\locks][\semi] = [0, 0, 0, 3, 5, 7, 10, 12, -12, -5].choose;

            if(0.55.coin) { st[\locks][\velocity] = rrand(0.35, 1.0) } { st[\locks][\velocity] = nil };
            if(0.35.coin) { st[\locks][\brightness] = rrand(0.0, 1.0) } { st[\locks][\brightness] = nil };
            if(0.35.coin) { st[\locks][\inharm] = rrand(0.0, 0.8) } { st[\locks][\inharm] = nil };
            if(0.30.coin) { st[\locks][\decay] = rrand(0.08, 2.5) } { st[\locks][\decay] = nil };
            if(0.25.coin) { st[\locks][\exciterType] = rrand(0, 5) } { st[\locks][\exciterType] = nil };
            if(0.20.coin) { st[\locks][\model] = rrand(0, 3) } { st[\locks][\model] = nil };
        };
    };

    ~plonkRandomizePattern = {
        ~plonkRandomizeOnePattern.(~plonkPatterns[~plonkSeq[\editVariation]]);
    };

    ~plonkRandomizePatternAndRefresh = {
        var wasRunning = ~plonkSeq[\isRunning];
        ~plonkRandomizePattern.();
        if(wasRunning) { ~plonkSeqStart.() };
    };

    // --------------------------------------------------------
    // save/load
    // --------------------------------------------------------
    ~plonkSaveSound = { |name="sound1"|
        var path = ~plonkV512SoundDir +/+ (name ++ ".archive");
        ~plonkState.copy.writeArchive(path);
        ("Saved sound: " ++ path).postln;
    };

    ~plonkLoadSound = { |name="sound1"|
        var path = ~plonkV512SoundDir +/+ (name ++ ".archive");
        if(File.exists(path)) {
            ~plonkState = Object.readArchive(path).copy;
            ("Loaded sound: " ++ path).postln;
        }{
            ("Sound not found: " ++ path).warn;
        };
    };

    ~plonkSavePattern = { |name="pattern1"|
        var path = ~plonkV512PatternDir +/+ (name ++ ".archive");
        (
            seq: ~plonkSeq.copy.put(\task, nil),
            patterns: ~plonkPatterns.collect { |arr| arr.collect(_.deepCopy) },
            mutate: ~plonkMutate.copy,
            pitch: ~plonkPitch.copy
        ).writeArchive(path);
        ("Saved pattern: " ++ path).postln;
    };

    ~plonkLoadPattern = { |name="pattern1"|
        var path = ~plonkV512PatternDir +/+ (name ++ ".archive");
        var obj;
        if(File.exists(path)) {
            obj = Object.readArchive(path);
            ~plonkSeq.putAll(obj[\seq].copy);
            ~plonkSeq[\task] = nil;
            ~plonkPatterns = obj[\patterns].collect { |arr| arr.collect(_.deepCopy) };
            ~plonkMutate = obj[\mutate].copy;
            if(obj[\pitch].notNil) {
                ~plonkPitch = obj[\pitch].copy;
            };
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

    MIDIdef.noteOn(\plonkV512On, { |vel, note|
        ~plonkTrigger.((freq: note.midicps, velocity: vel / 127));
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
        var soundField, patternField, baseMidiLabel, stepNoteLabel, condSummaryLabel, chainSummaryLabel;
        var copiedVariation = nil;
        var lockStep = 0;
        var lockBoxes = IdentityDictionary.new;
        var lockEnableButtons = IdentityDictionary.new;
        var showPage, refreshControls, refreshPatternUI, refreshLockEditor, refreshVarButtons, refreshChainUI;
        var makeButton, makePage, makeSlider, makeMenu, makeBoundedBox;
        var modelNames = ["Bar", "Plate", "Bell", "Drum"];
        var exciterNames = ["Mallet", "HardPick", "Brush", "Scrape", "Burst", "ImpulseCluster"];
        var varButtons = Array.newClear(4);
        var fillButton, mutateEnableButton, copyVarButton, pasteVarButton, dupVarButton, chainEnableButton, allEditChainButton, randSelButton;
        var chainVarMenus = Array.newClear(4);
        var chainBarBoxes = Array.newClear(4);
        var rangeSrcABox, rangeSrcBBox, rangeDstBox;
        var rootMenu, scaleMenu, layerModeMenu, eng2ModelMenu, eng2ExcMenu;

        ~plonkStepIndicators = stepIndicators;
        ~plonkStepButtons = stepButtons;

        win = Window("Plonk-ish v5.12", Rect(0, 40, 1498, 940)).front;
        win.alwaysOnTop_(false);
        win.userCanClose_(true);
        win.setInnerExtent(1450, 740);

        uiW = win.view.bounds.width.asInteger;
        uiH = win.view.bounds.height.asInteger;

        header = View(win, Rect(0, 0, uiW, 64));
        content = View(win, Rect(0, 66, uiW, uiH - 66));

        header.resize_(2);
        content.resize_(5);

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
            pages.keysValuesDo { |k, v| v.visible_(k == key) };
        };

        makeSlider = { |parent, x, y, label, key, min=0.0, max=1.0, spec=\lin|
            var st = StaticText(parent, Rect(x, y, 110, 20));
            var sl = Slider(parent, Rect(x + 110, y + 3, 220, 16));
            var nb = NumberBox(parent, Rect(x + 338, y, 70, 20));

            st.string_(label);

            sl.action_({
                var v;
                if(spec == \exp) {
                    v = sl.value.linexp(0, 1, min.max(0.0001), max);
                }{
                    v = sl.value.linlin(0, 1, min, max);
                };
                v = v.clip(min, max);
                ~plonkState[key] = v;
                nb.value_(v);
            });

            nb.action_({
                var v = nb.value.clip(min, max);
                var norm;
                if(spec == \exp) {
                    norm = v.explin(min.max(0.0001), max, 0, 1);
                }{
                    norm = v.linlin(min, max, 0, 1);
                };
                ~plonkState[key] = v;
                sl.value_(norm.clip(0, 1));
            });

            controls[key] = (type: \slider, slider: sl, box: nb, min: min, max: max, spec: spec);
        };

        makeMenu = { |parent, x, y, label, key, items|
            var st = StaticText(parent, Rect(x, y, 110, 20));
            var pm = PopUpMenu(parent, Rect(x + 110, y, 220, 20));
            st.string_(label);
            pm.items_(items);
            pm.action_({ ~plonkState[key] = pm.value });
            controls[key] = (type: \menu, menu: pm);
        };

        refreshControls = {
            controls.keysValuesDo { |k, c|
                var v = ~plonkState[k];
                var norm;
                if(c[\type] == \slider) {
                    if(c[\spec] == \exp) {
                        norm = v.explin(c[\min].max(0.0001), c[\max], 0, 1);
                    }{
                        norm = v.linlin(c[\min], c[\max], 0, 1);
                    };
                    c[\slider].value_(norm.clip(0, 1));
                    c[\box].value_(v);
                }{
                    c[\menu].value_(v.asInteger);
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
                    "Chain Pos: " ++ (~plonkSeq[\chainIndex] + 1).asString
                    ++ " | Bar: " ++ ~plonkSeq[\chainBarCount].asString
                    ++ " | Play Var: " ++ ~plonkVariationNames[~plonkCurrentPlaybackVariation.()]
                );
            };
        };

        refreshPatternUI = {
            32.do { |i|
                var st = ~plonkSteps[i];
                var isActive = i < ~plonkSeq[\steps];
                var noteName = ~plonkMidiToName.(~plonkStepMidiForIndex.(i));
                var layerTag = switch((st[\layerMode] ? 0).asInteger,
    1, {
        switch((st[\engine2PitchMode] ? 0).asInteger, 1, { "L:S" }, 2, { "L:D" }, { "L" })
    },
    2, { "A" },
    3, { "R" },
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

                    stepButtons[i].value_(st[\on]);
                };

                if(stepEditButtons[i].notNil) {
                    stepEditButtons[i].enabled_(isActive);
                };

                if(stepIndicators[i].notNil) {
                    if(i == ~plonkSeq[\currentStep]) {
                        stepIndicators[i].string_("▶");
                    }{
                        stepIndicators[i].string_(" ");
                    };
                };

                if(stepLabels[i].notNil) {
                    if(isActive) {
                        stepLabels[i].string_((i + 1).asString);
                    }{
                        stepLabels[i].string_((i + 1).asString ++ " x");
                    };
                };

                if(stepNoteMiniLabels[i].notNil) {
                    if(isActive) {
                        stepNoteMiniLabels[i].string_(noteName);
                    }{
                        stepNoteMiniLabels[i].string_("-");
                    };
                };

                if(condMiniLabels[i].notNil) {
                    if(isActive) {
                        condMiniLabels[i].string_(
                            ~plonkCondShortName.(st)
                            ++ if((st[\tie] ? 0) == 1) { " T" } { "" }
                            ++ if(layerTag != "") { " " ++ layerTag } { "" }
                        );
                    }{
                        condMiniLabels[i].string_("-");
                    };
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
                    "Edit: " ++ ~plonkVariationNames[~plonkSeq[\editVariation]]
                    ++ " | Play: " ++ ~plonkVariationNames[~plonkCurrentPlaybackVariation.()]
                    ++ " | Cycle: " ++ ~plonkSeq[\cycleCount].asString
                );
            };

            refreshVarButtons.();
            refreshChainUI.();
        };

        refreshLockEditor = {
            var st = ~plonkSteps[lockStep];
            var locks = st[\locks];

            if(lockBoxes[\stepNum].notNil) { lockBoxes[\stepNum].value_(lockStep) };
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
            if(layerModeMenu.notNil) { layerModeMenu.value_((st[\layerMode] ? 0).asInteger) };
            if(eng2ModelMenu.notNil) { eng2ModelMenu.value_((st[\engine2Model] ? 3).asInteger) };
            if(eng2ExcMenu.notNil) { eng2ExcMenu.value_((st[\engine2Exciter] ? 2).asInteger) };
            if(lockBoxes[\layerLevel].notNil) { lockBoxes[\layerLevel].value_(st[\layerLevel] ? 0.60) };
			if(lockBoxes[\engine2PitchMode].notNil) { lockBoxes[\engine2PitchMode].value_((st[\engine2PitchMode] ? 0).asInteger) };
			if(lockBoxes[\engine2SemiOffset].notNil) { lockBoxes[\engine2SemiOffset].value_(st[\engine2SemiOffset] ? 0) };
			if(lockBoxes[\engine2DegreeOffset].notNil) { lockBoxes[\engine2DegreeOffset].value_(st[\engine2DegreeOffset] ? 0) };
			if(lockBoxes[\engine2DegreeOctOffset].notNil) { lockBoxes[\engine2DegreeOctOffset].value_(st[\engine2DegreeOctOffset] ? 0) };
			if(lockBoxes[\engine2DecayMul].notNil) { lockBoxes[\engine2DecayMul].value_(st[\engine2DecayMul] ? 1.00) };
			if(lockBoxes[\engine2NoiseOffset].notNil) { lockBoxes[\engine2NoiseOffset].value_(st[\engine2NoiseOffset] ? 0.00) };
			if(lockBoxes[\engine2ClickOffset].notNil) { lockBoxes[\engine2ClickOffset].value_(st[\engine2ClickOffset] ? 0.00) };
			if(lockBoxes[\engine2PanOffset].notNil) { lockBoxes[\engine2PanOffset].value_(st[\engine2PanOffset] ? 0.00) };

            ~plonkLockKeys.do { |k|
                var enKey = (k.asString ++ "_en").asSymbol;
                var v = locks[k];

                if(lockEnableButtons[enKey].notNil) {
                    if((k == \semi) or: { k == \useDegree } or: { k == \degree } or: { k == \degreeOct }) {
                        if(k == \semi) {
                            lockEnableButtons[enKey].value_(1);
                        };
                    }{
                        lockEnableButtons[enKey].value_(v.notNil.asInteger);
                    };
                };

                if(lockBoxes[k].notNil) {
                    if(v.notNil) {
                        lockBoxes[k].value_(v);
                    }{
                        if((k != \semi) and: { k != \degree } and: { k != \degreeOct }) {
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

        Button(header, Rect(680, 16, 80, 28))
        .states_([
            ["Trigger", Color.white, Color(0.9, 0.7, 0.0)]
        ])
        .action_({
            ~plonkTrigger.(());
        });

        makeButton.(header, Rect(820, 16, 55, 28), "Bar", { ~plonkModelPresets.(0); refreshControls.() });
        makeButton.(header, Rect(880, 16, 55, 28), "Plate", { ~plonkModelPresets.(1); refreshControls.() });
        makeButton.(header, Rect(940, 16, 55, 28), "Bell", { ~plonkModelPresets.(2); refreshControls.() });
        makeButton.(header, Rect(1000, 16, 55, 28), "Drum", { ~plonkModelPresets.(3); refreshControls.() });

        makeButton.(header, Rect(1100, 16, 80, 28), "RandPat", {
            ~plonkRandomizePatternAndRefresh.();
            refreshPatternUI.();
            refreshLockEditor.();
        });

        // main page
        {
            var v = makePage.(\main), y = 20;
            StaticText(v, Rect(20, 0, 500, 20)).string_("Main controls + presets");
            makeMenu.(v, 20, y, "Model", \model, modelNames); y = y + 28;
            makeMenu.(v, 20, y, "Exciter", \exciterType, exciterNames); y = y + 28;
            makeSlider.(v, 20, y, "Freq", \freq, 40, 4000, \exp); y = y + 28;
            makeSlider.(v, 20, y, "Amp", \amp, 0.01, 0.6, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Pan", \pan, -1.0, 1.0, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Velocity", \velocity, 0.0, 1.0, \lin); y = y + 28;

            y = y + 20;

            StaticText(v, Rect(20, y, 120, 20)).string_("Sound Preset");
            soundField = TextField(v, Rect(140, y, 140, 20)).string_("sound1");
            makeButton.(v, Rect(290, y - 1, 60, 22), "Save", {
                ~plonkSaveSound.(soundField.string);
            });
            makeButton.(v, Rect(356, y - 1, 60, 22), "Load", {
                ~plonkLoadSound.(soundField.string);
                refreshControls.();
            });
            y = y + 34;

            StaticText(v, Rect(20, y, 120, 20)).string_("Pattern Preset");
            patternField = TextField(v, Rect(140, y, 140, 20)).string_("pattern1");
            makeButton.(v, Rect(290, y - 1, 60, 22), "Save", {
                ~plonkSavePattern.(patternField.string);
            });
            makeButton.(v, Rect(356, y - 1, 60, 22), "Load", {
                ~plonkLoadPattern.(patternField.string);
                refreshPatternUI.();
                refreshLockEditor.();
            });
        }.value;

        // exciter page
        {
            var v = makePage.(\exciter), y = 20;
            StaticText(v, Rect(20, 0, 500, 20)).string_("Exciter");
            makeMenu.(v, 20, y, "Exciter", \exciterType, exciterNames); y = y + 28;
            makeSlider.(v, 20, y, "Tone", \tone, 0, 1, \lin); y = y + 28;
            makeSlider.(v, 20, y, "NoiseAmt", \noiseAmt, 0, 1.2, \lin); y = y + 28;
            makeSlider.(v, 20, y, "ClickAmt", \clickAmt, 0, 2.0, \lin); y = y + 28;
            makeSlider.(v, 20, y, "ExcDecay", \excDecay, 0.001, 0.12, \exp); y = y + 28;
        }.value;

        // resonator page
        {
            var v = makePage.(\res), y = 20;
            StaticText(v, Rect(20, 0, 500, 20)).string_("Resonator");
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

        // performance page
        {
            var v = makePage.(\perf), y = 20;
            StaticText(v, Rect(20, 0, 500, 20)).string_("Performance");
            makeSlider.(v, 20, y, "Drive", \drive, 0.7, 2.0, \lin); y = y + 28;
            makeSlider.(v, 20, y, "PitchEnvAmt", \pitchEnvAmt, 0, 0.4, \lin); y = y + 28;
            makeSlider.(v, 20, y, "PitchEnvDec", \pitchEnvDecay, 0.005, 0.12, \exp); y = y + 28;
            makeSlider.(v, 20, y, "Vel->Bright", \velToBright, 0, 0.6, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Vel->Decay", \velToDecay, 0, 0.5, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Vel->Noise", \velToNoise, 0, 0.5, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Vel->Click", \velToClick, 0, 0.5, \lin); y = y + 28;
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

            StaticText(v, Rect(20, 0, 420, 20)).string_("Pattern + playhead (32-step UI)");
            condSummaryLabel = StaticText(v, Rect(460, 0, 400, 20));
            chainSummaryLabel = StaticText(v, Rect(860, 0, 520, 20));

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
                if(baseMidiLabel.notNil) {
                    baseMidiLabel.string_(~plonkMidiToName.(~plonkSeq[\baseMidi]));
                };
                if(stepNoteLabel.notNil) {
                    stepNoteLabel.string_(
                        "Resulting Note: " ++
                        ~plonkMidiToName.(~plonkStepMidiForIndex.(lockStep))
                    );
                };
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
            .states_([
                ["Run", Color.white, Color.green(0.75)]
            ])
            .action_({
                ~plonkSeqStart.();
            });

            Button(v, Rect(816, y1 - 1, 50, 22))
            .states_([
                ["Stop", Color.white, Color.red(0.8)]
            ])
            .action_({
                ~plonkSeqStop.();
            });

            StaticText(v, Rect(20, y2, 58, 20)).string_("Variation");
            4.do { |i|
                varButtons[i] = Button(v, Rect(82 + (i * 32), y2 - 1, 28, 22))
                .states_([[~plonkVariationNames[i]]])
                .action_({
                    ~plonkSeq[\activeVariation] = i;
                    ~plonkSetEditVariation.(i);
                    refreshPatternUI.();
                    refreshLockEditor.();
                });
            };

            fillButton = Button(v, Rect(216, y2 - 1, 40, 22))
            .states_([["Fill"]])
            .action_({
                ~plonkSeq[\fillMode] = fillButton.value == 1;
                refreshVarButtons.();
                refreshPatternUI.();
            });

            copyVarButton = Button(v, Rect(262, y2 - 1, 44, 22))
            .states_([["Copy"]])
            .action_({
                copiedVariation = ~plonkPatterns[~plonkSeq[\editVariation]].collect(_.deepCopy);
            });

            pasteVarButton = Button(v, Rect(310, y2 - 1, 44, 22))
            .states_([["Paste"]])
            .action_({
                if(copiedVariation.notNil) {
                    ~plonkPatterns[~plonkSeq[\editVariation]] = copiedVariation.collect(_.deepCopy);
                    ~plonkSetEditVariation.(~plonkSeq[\editVariation]);
                    refreshPatternUI.();
                    refreshLockEditor.();
                };
            });

            dupVarButton = Button(v, Rect(358, y2 - 1, 56, 22))
            .states_([["Dup->"]])
            .action_({
                var src, dst;
                src = ~plonkSeq[\editVariation];
                dst = (src + 1) % 4;
                ~plonkPatterns[dst] = ~plonkPatterns[src].collect(_.deepCopy);
                refreshPatternUI.();
                refreshLockEditor.();
            });

            randSelButton = Button(v, Rect(420, y2 - 1, 58, 22))
            .states_([["Rand Sel"]])
            .action_({
                ~plonkRandomizePattern.();
                refreshPatternUI.();
                refreshLockEditor.();
            });

            StaticText(v, Rect(520, y2, 52, 20)).string_("Mutation");
            mutateEnableButton = Button(v, Rect(576, y2 - 1, 58, 22))
            .states_([
                ["Mut Off", Color.black, Color.grey(0.85)],
                ["Mut On", Color.white, Color(0.20, 0.60, 0.20)]
            ])
            .action_({ |bt|
                ~plonkMutate[\enabled] = (bt.value == 1);
                refreshVarButtons.();
                refreshPatternUI.();
            });

            StaticText(v, Rect(642, y2, 22, 20)).string_("Ev");
            mutateEveryBox = makeBoundedBox.(v, Rect(664, y2, 42, 20), ~plonkMutate[\everyCycles], 1, 32, 1, 0, { |nb, val|
                ~plonkMutate[\everyCycles] = val.asInteger;
            });

            StaticText(v, Rect(714, y2, 28, 20)).string_("Amt");
            mutateAmtBox = makeBoundedBox.(v, Rect(742, y2, 50, 20), ~plonkMutate[\amount], 0, 1, 0.01, 2, { |nb, val|
                ~plonkMutate[\amount] = val;
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

                StaticText(v, Rect(x + 68, y3, 24, 20)).string_("Br");
                chainBarBoxes[i] = makeBoundedBox.(v, Rect(x + 92, y3, 26, 20), (~plonkSeq[\chainSlots][i][\bars] ? 1), 1, 8, 1, 0, { |nb, val|
                    ~plonkSeq[\chainSlots][i][\bars] = val.asInteger.max(1);
                    refreshPatternUI.();
                });
            };

            StaticText(v, Rect(20, y4, 50, 20)).string_("Utils");

            Button(v, Rect(74, y4 - 1, 78, 22))
            .states_([["Clear Var"]])
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

            StaticText(v, Rect(260, y4, 52, 20)).string_("CopyRange");
            StaticText(v, Rect(318, y4, 18, 20)).string_("A");
            rangeSrcABox = makeBoundedBox.(v, Rect(334, y4, 42, 20), 0, 0, 31, 1, 0, { |nb, val| });

            StaticText(v, Rect(384, y4, 18, 20)).string_("B");
            rangeSrcBBox = makeBoundedBox.(v, Rect(400, y4, 42, 20), 3, 0, 31, 1, 0, { |nb, val| });

            StaticText(v, Rect(450, y4, 24, 20)).string_("Dst");
            rangeDstBox = makeBoundedBox.(v, Rect(476, y4, 42, 20), 8, 0, 31, 1, 0, { |nb, val| });

            Button(v, Rect(526, y4 - 1, 46, 22))
            .states_([["Do"]])
            .action_({
                ~plonkCopyStepRangeInCurrentVariation.(
                    rangeSrcABox.value.asInteger,
                    rangeSrcBBox.value.asInteger,
                    rangeDstBox.value.asInteger
                );
                refreshPatternUI.();
                refreshLockEditor.();
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
    var rowGap = 24;
    var addLockRow;
    var condMenu;
    var pageTitle;

    var yTitle = 8;
    var yRow1 = 64;    // basic step params
    var yRow2 = 108;   // degree + condition
    var yRow3 = 176;   // layer row 1
    var yRow4 = 214;   // layer row 2
    var yLocks = 304;  // lock matrix start
    var yBottom = 604; // bottom buttons

    // lock matrix layout
    var col1X = 28;
    var col2X = 470;
    var labelW = 108;
    var toggleW = 48;
    var valueW = 90;
    var valueGap = 10;

    // section helpers
    var sectionHdr, sectionLine, sectionPanel;

    sectionHdr = { |x, y, text|
        var t = StaticText(v, Rect(x, y, 260, 20));
        t.string_(text);
        t.font_(Font.default.boldVariant.size_(13));
        t;
    };

    sectionLine = { |x, y, w=1280|
        var u = UserView(v, Rect(x, y, w, 1));
        u.background_(Color.grey(0.72));
        u;
    };

    sectionPanel = { |x, y, w, h, color|
        var p = UserView(v, Rect(x, y, w, h));
        p.background_(color);
        p;
    };

    // --------------------------------------------------
    // page title
    // --------------------------------------------------
    pageTitle = StaticText(v, Rect(20, yTitle, 420, 28));
    pageTitle.string_("Per-step Editor");
    pageTitle.font_(Font.default.boldVariant.size_(18));

    // --------------------------------------------------
    // subtle tinted background panels
    // --------------------------------------------------
    sectionPanel.(16, 36, 1185, 110, Color(0.95, 0.95, 0.93));// timing + conditions
    sectionPanel.(16, 146, 1185, 110, Color(0.93, 0.95, 0.97)); // layering
    sectionPanel.(16, 274, 920, 278, Color(0.95, 0.94, 0.96));  // lock matrix
    sectionPanel.(16, 594, 420, 46, Color(0.94, 0.94, 0.94));   // bottom actions

    // --------------------------------------------------
    // SECTION 1: TIMING + CONDITIONS
    // --------------------------------------------------
    sectionHdr.(20, 40, "Timing + Conditions");
    sectionLine.(20, 58, 1160);

    StaticText(v, Rect(20, yRow1, 80, 20)).string_("Step");
    lockBoxes[\stepNum] = makeBoundedBox.(v, Rect(100, yRow1, 50, 20), 0, 0, 31, 1, 0, { |nb, val|
        lockStep = val.asInteger;
        refreshLockEditor.();
    });

    lockEnableButtons[\on] = Button(v, Rect(170, yRow1 - 2, 60, 24))
    .states_([["Off"], ["On"]])
    .action_({ |bt|
        ~plonkSteps[lockStep][\on] = bt.value;
        refreshPatternUI.();
    });

    StaticText(v, Rect(250, yRow1, 44, 20)).string_("Prob");
    lockBoxes[\prob] = makeBoundedBox.(v, Rect(294, yRow1, 60, 20), 1.0, 0, 1, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\prob] = val;
    });

    StaticText(v, Rect(370, yRow1, 52, 20)).string_("Rat");
    lockBoxes[\ratchet] = makeBoundedBox.(v, Rect(420, yRow1, 60, 20), 1, 1, 4, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\ratchet] = val.asInteger;
    });

    StaticText(v, Rect(500, yRow1, 52, 20)).string_("Micro");
    lockBoxes[\micro] = makeBoundedBox.(v, Rect(552, yRow1, 60, 20), 0.0, -0.49, 0.49, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\micro] = val;
    });

    StaticText(v, Rect(630, yRow1, 44, 20)).string_("Gate");
    lockBoxes[\gate] = makeBoundedBox.(v, Rect(674, yRow1, 60, 20), 0.85, 0.05, 1.25, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\gate] = val;
    });

    StaticText(v, Rect(750, yRow1, 54, 20)).string_("Accent");
    lockBoxes[\accent] = makeBoundedBox.(v, Rect(806, yRow1, 60, 20), 0.0, 0, 1, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\accent] = val;
    });

    StaticText(v, Rect(880, yRow1, 34, 20)).string_("Len");
    lockBoxes[\length] = makeBoundedBox.(v, Rect(912, yRow1, 44, 20), 1, 1, 8, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\length] = val.asInteger.clip(1, 8);
    });

    lockEnableButtons[\tie] = Button(v, Rect(972, yRow1 - 2, 68, 24))
    .states_([["Tie Off"], ["Tie On"]])
    .action_({ |bt|
        ~plonkSteps[lockStep][\tie] = bt.value;
        refreshPatternUI.();
    });

    stepNoteLabel = StaticText(v, Rect(1060, yRow1, 260, 20));
    stepNoteLabel.string_("Resulting Note: " ++ ~plonkMidiToName.(~plonkSeq[\baseMidi]));

    StaticText(v, Rect(20, yRow2, 64, 20)).string_("UseDeg");
    lockEnableButtons[\useDegree] = Button(v, Rect(86, yRow2 - 2, 58, 24))
    .states_([["Off"], ["On"]])
    .action_({ |bt|
        ~plonkSteps[lockStep][\locks][\useDegree] = bt.value;
        refreshPatternUI.();
        refreshLockEditor.();
    });

    StaticText(v, Rect(160, yRow2, 54, 20)).string_("Degree");
    lockBoxes[\degree] = makeBoundedBox.(v, Rect(216, yRow2, 52, 20), 0, -14, 14, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\locks][\degree] = val.asInteger;
        refreshPatternUI.();
        refreshLockEditor.();
    });

    StaticText(v, Rect(280, yRow2, 52, 20)).string_("DegOct");
    lockBoxes[\degreeOct] = makeBoundedBox.(v, Rect(334, yRow2, 52, 20), 0, -3, 3, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\locks][\degreeOct] = val.asInteger;
        refreshPatternUI.();
        refreshLockEditor.();
    });

    StaticText(v, Rect(400, yRow2, 90, 20)).string_("Condition");
    condMenu = PopUpMenu(v, Rect(492, yRow2, 140, 20));
    condMenu.items_(~plonkCondNames);
    condMenu.action_({
        ~plonkSteps[lockStep][\condType] = condMenu.value;
        refreshPatternUI.();
    });
    lockBoxes[\condType] = condMenu;

    StaticText(v, Rect(646, yRow2, 20, 20)).string_("A");
    lockBoxes[\condA] = makeBoundedBox.(v, Rect(666, yRow2, 48, 20), 1, 1, 16, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\condA] = val.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(726, yRow2, 20, 20)).string_("B");
    lockBoxes[\condB] = makeBoundedBox.(v, Rect(746, yRow2, 48, 20), 2, 1, 16, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\condB] = val.asInteger;
        refreshPatternUI.();
    });

    // --------------------------------------------------
    // SECTION 2: LAYERING
    // --------------------------------------------------
    sectionHdr.(20, 150, "Layering");
    sectionLine.(20, 168, 1160);

    StaticText(v, Rect(20, yRow3, 74, 20)).string_("LayerMode");
    layerModeMenu = PopUpMenu(v, Rect(96, yRow3, 100, 20));
    layerModeMenu.items_(~plonkLayerModeNames);
    layerModeMenu.action_({
        ~plonkSteps[lockStep][\layerMode] = layerModeMenu.value.asInteger;
        refreshPatternUI.();
    });

    StaticText(v, Rect(212, yRow3, 74, 20)).string_("Eng2Model");
    eng2ModelMenu = PopUpMenu(v, Rect(288, yRow3, 84, 20));
    eng2ModelMenu.items_(modelNames);
    eng2ModelMenu.action_({
        ~plonkSteps[lockStep][\engine2Model] = eng2ModelMenu.value.asInteger;
    });

    StaticText(v, Rect(388, yRow3, 62, 20)).string_("Eng2Exc");
    eng2ExcMenu = PopUpMenu(v, Rect(452, yRow3, 110, 20));
    eng2ExcMenu.items_(exciterNames);
    eng2ExcMenu.action_({
        ~plonkSteps[lockStep][\engine2Exciter] = eng2ExcMenu.value.asInteger;
    });

    StaticText(v, Rect(578, yRow3, 54, 20)).string_("LayerLvl");
    lockBoxes[\layerLevel] = makeBoundedBox.(v, Rect(636, yRow3, 52, 20), 0.60, 0.05, 1.0, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\layerLevel] = val;
    });

    StaticText(v, Rect(696, yRow3, 58, 20)).string_("Pitch2");
    lockBoxes[\engine2PitchMode] = PopUpMenu(v, Rect(752, yRow3, 78, 20));
    lockBoxes[\engine2PitchMode].items_(["Follow", "Semi", "Degree"]);
    lockBoxes[\engine2PitchMode].action_({
        ~plonkSteps[lockStep][\engine2PitchMode] = lockBoxes[\engine2PitchMode].value.asInteger;
    });

    StaticText(v, Rect(838, yRow3, 44, 20)).string_("Semi2");
    lockBoxes[\engine2SemiOffset] = makeBoundedBox.(v, Rect(882, yRow3, 46, 20), 0, -24, 24, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\engine2SemiOffset] = val.asInteger;
    });

    StaticText(v, Rect(936, yRow3, 40, 20)).string_("Deg2");
    lockBoxes[\engine2DegreeOffset] = makeBoundedBox.(v, Rect(976, yRow3, 46, 20), 0, -14, 14, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\engine2DegreeOffset] = val.asInteger;
    });

    StaticText(v, Rect(1030, yRow3, 42, 20)).string_("Oct2");
    lockBoxes[\engine2DegreeOctOffset] = makeBoundedBox.(v, Rect(1074, yRow3, 42, 20), 0, -3, 3, 1, 0, { |nb, val|
        ~plonkSteps[lockStep][\engine2DegreeOctOffset] = val.asInteger;
    });

    StaticText(v, Rect(20, yRow4, 72, 20)).string_("Eng2DecMul");
    lockBoxes[\engine2DecayMul] = makeBoundedBox.(v, Rect(96, yRow4, 58, 20), 1.00, 0.20, 3.00, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\engine2DecayMul] = val;
    });

    StaticText(v, Rect(170, yRow4, 64, 20)).string_("Eng2Noise+");
    lockBoxes[\engine2NoiseOffset] = makeBoundedBox.(v, Rect(238, yRow4, 58, 20), 0.00, -1.2, 1.2, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\engine2NoiseOffset] = val;
    });

    StaticText(v, Rect(312, yRow4, 60, 20)).string_("Eng2Click+");
    lockBoxes[\engine2ClickOffset] = makeBoundedBox.(v, Rect(376, yRow4, 58, 20), 0.00, -2.0, 2.0, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\engine2ClickOffset] = val;
    });

    StaticText(v, Rect(450, yRow4, 52, 20)).string_("Eng2Pan+");
    lockBoxes[\engine2PanOffset] = makeBoundedBox.(v, Rect(506, yRow4, 58, 20), 0.00, -1.0, 1.0, 0.01, 2, { |nb, val|
        ~plonkSteps[lockStep][\engine2PanOffset] = val;
    });

    // --------------------------------------------------
    // SECTION 3: PER-STEP LOCKS
    // --------------------------------------------------
    sectionHdr.(20, 278, "Per-step Locks");
    sectionLine.(20, 296, 900);

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

    // --------------------------------------------------
    // bottom actions
    // --------------------------------------------------
    makeButton.(v, Rect(20, yBottom, 90, 24), "Trig Step", {
        var st = ~plonkSteps[lockStep];
        if(st[\on] == 0) { st[\on] = 1 };
        ~plonkTriggerStepVoices.(st, 0.35, lockStep);
        refreshPatternUI.();
    });

    makeButton.(v, Rect(120, yBottom, 90, 24), "Clear", {
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

    makeButton.(v, Rect(220, yBottom, 90, 24), "Copy", {
        ~copiedPlonkStep = ~plonkSteps[lockStep].deepCopy;
    });

    makeButton.(v, Rect(320, yBottom, 90, 24), "Paste", {
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

        refreshControls.();
        ~plonkSetEditVariation.(0);
        refreshPatternUI.();
        refreshLockEditor.();
        ~plonkRefreshAudioMenus.();
        showPage.(\main);

        win.onClose_({
            ~plonkSeqStop.();
            MIDIdef.noteOn(\plonkV512On).free;
            ~plonkVoices.do { |entry| entry[\synth].set(\gate, 0) };
            ~plonkVoices.clear;
        });
    }.defer;

});
)
