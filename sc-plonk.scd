(
// ============================================================
// Plonk-ish v5.4
// - 32-step UI
// - disabled steps beyond active pattern length
// - Base Note shows note name
// - Step editor shows resulting note
// - Pattern page shows note labels per step
// ============================================================

// ---------- pre-boot server options ----------
s.options.memSize = 262144;
s.options.numWireBufs = 128;

s.waitForBoot({

    // --------------------------------------------------------
    // paths
    // --------------------------------------------------------
    ~plonkEnsureDir = { |p|
        if(File.exists(p).not) {
            ("mkdir -p " ++ p.quote).unixCmd;
        };
    };

    ~plonkV54SoundDir = Platform.userHomeDir +/+ "PlonkV54_Sounds";
    ~plonkV54PatternDir = Platform.userHomeDir +/+ "PlonkV54_Patterns";

    ~plonkEnsureDir.(~plonkV54SoundDir);
    ~plonkEnsureDir.(~plonkV54PatternDir);

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

    ~plonkStepMidiForIndex = { |idx|
        var semi;
        semi = (~plonkSteps[idx][\locks][\semi] ? 0).asInteger;
        (~plonkSeq[\baseMidi] + semi).clip(0, 127);
    };

    // --------------------------------------------------------
    // synth definition
    // --------------------------------------------------------
    ~plonkDefineSynth = {
        SynthDef(\plonkV54, {
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
                    (baseFreq * harmBlend * (1 + Rand((detune + bankDetune).neg, (detune + bankDetune)))).clip(20, 20000)
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
    "Loaded \\plonkV54".postln;

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

        MIDIdef.noteOn(\plonkV54On, { |vel, note|
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
        MIDIdef.noteOn(\plonkV54On).free;

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
    ~plonkMaxVoices = 8;

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
        synth = Synth(\plonkV54, args.asKeyValuePairs);
        ~plonkVoices.add((synth: synth, model: args[\model], time: Main.elapsedTime));

        synth.onFree({
            { ~plonkVoices = ~plonkVoices.select { |entry| entry[\synth] != synth } }.defer;
        });

        synth;
    };

    // --------------------------------------------------------
    // sequencer
    // --------------------------------------------------------
    ~plonkLockKeys = [
        \semi, \velocity, \decay, \brightness, \material, \inharm, \position,
        \body, \damp, \drive, \tone, \noiseAmt, \clickAmt, \exciterType,
        \model, \pitchEnvAmt, \pitchEnvDecay, \detune, \spread, \pan
    ];

    ~makePlonkStep = { |on=0|
        (
            on: on,
            prob: 1.0,
            ratchet: 1,
            micro: 0.0,
            gate: 0.85,
            accent: 0.0,
            locks: (
                semi: 0, velocity: nil, decay: nil, brightness: nil, material: nil, inharm: nil,
                position: nil, body: nil, damp: nil, drive: nil, tone: nil, noiseAmt: nil,
                clickAmt: nil, exciterType: nil, model: nil, pitchEnvAmt: nil,
                pitchEnvDecay: nil, detune: nil, spread: nil, pan: nil
            )
        )
    };

    ~plonkSeq = (
        tempo: 120, swing: 0.0, steps: 32, baseMidi: 48,
        isRunning: false, task: nil, currentStep: -1
    );

    ~plonkSteps = Array.fill(32, { |i| ~makePlonkStep.(if(i % 4 == 0) { 1 } { 0 }) });

    ~plonkBuildStepArgs = { |step|
        var args = ~plonkState.copy;
        var locks = step[\locks];
        var noteMidi = ~plonkSeq[\baseMidi] + (locks[\semi] ? 0);
        var accentAmt = step[\accent].clip(0, 1);

        args[\freq] = noteMidi.midicps;
        if(locks[\velocity].notNil) { args[\velocity] = locks[\velocity] };

        ~plonkLockKeys.do { |k|
            if((k != \semi) and: { locks[k].notNil }) { args[k] = locks[k] };
        };

        args[\velocity] = (args[\velocity] + (accentAmt * 0.20)).clip(0, 1);
        args[\brightness] = (args[\brightness] + (accentAmt * 0.10)).clip(0, 1);
        args[\clickAmt] = (args[\clickAmt] + (accentAmt * 0.18)).clip(0, 2.0);
        args[\drive] = (args[\drive] + (accentAmt * 0.08)).clip(0.7, 2.0);

        args;
    };

    ~plonkRefreshPlayhead = {
        if(~plonkStepIndicators.notNil) {
            {
                32.do { |i|
                    if(~plonkStepIndicators[i].notNil) {
                        if(i == ~plonkSeq[\currentStep]) {
                            ~plonkStepIndicators[i].string_("▶");
                        }{
                            ~plonkStepIndicators[i].string_(" ");
                        };
                    };
                };
            }.defer;
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
        var st, baseDur, stepDur, swing, microOffset, ratchetDur, args;

        st = ~plonkSteps[stepIndex];
        baseDur = (60 / ~plonkSeq[\tempo]) / 4;
        swing = ~plonkSeq[\swing].clip(0, 0.49);

        if(stepIndex.odd) {
            stepDur = baseDur * (1 + swing);
        }{
            stepDur = baseDur * (1 - swing);
        };

        ~plonkSeq[\currentStep] = stepIndex;
        ~plonkRefreshPlayhead.();

        if(st[\on] == 1 and: { 1.0.rand <= st[\prob] }) {
            microOffset = st[\micro].clip(-0.49, 0.49) * (stepDur * 0.5);
            ratchetDur = stepDur / st[\ratchet].clip(1, 4);
            args = ~plonkBuildStepArgs.(st);

            if(microOffset > 0) { microOffset.wait };

            st[\ratchet].clip(1, 4).do { |i|
                var synth, gateDur;
                synth = ~plonkTrigger.(args);
                gateDur = (ratchetDur * st[\gate].clip(0.05, 1.25)).max(0.01);

                AppClock.sched(gateDur, {
                    synth.set(\gate, 0);
                    nil
                });

                if(i < (st[\ratchet].clip(1, 4) - 1)) {
                    ratchetDur.wait;
                };
            };

            if(microOffset < 0) {
                (stepDur + microOffset.abs).wait;
            }{
                (stepDur - microOffset).max(0.001).wait;
            };
        }{
            stepDur.wait;
        };
    };

    ~plonkSeqStart = {
        ~plonkSeqStop.();
        ~plonkSeq[\isRunning] = true;

        ~plonkSeq[\task] = Task({
            var idx = 0;
            loop {
                ~plonkPlayLiveStep.(idx);
                idx = (idx + 1) % ~plonkSeq[\steps].clip(1, 32);
            };
        }).play(AppClock);
    };

    ~plonkRandomizePattern = {
        32.do { |i|
            var st = ~plonkSteps[i];
            st[\on] = [0, 1].wchoose([0.4, 0.6]);
            st[\prob] = rrand(0.45, 1.0);
            st[\ratchet] = [1, 1, 1, 2, 2, 3, 4].choose;
            st[\micro] = rrand(-0.18, 0.18);
            st[\gate] = rrand(0.35, 1.10);
            st[\accent] = [0.0, 0.0, 0.25, 0.5, 0.75, 1.0].choose;

            st[\locks][\semi] = [0, 0, 0, 3, 5, 7, 10, 12, -12, -5].choose;

            if(0.55.coin) { st[\locks][\velocity] = rrand(0.35, 1.0) } { st[\locks][\velocity] = nil };
            if(0.35.coin) { st[\locks][\brightness] = rrand(0.0, 1.0) } { st[\locks][\brightness] = nil };
            if(0.30.coin) { st[\locks][\decay] = rrand(0.08, 2.5) } { st[\locks][\decay] = nil };
            if(0.25.coin) { st[\locks][\exciterType] = rrand(0, 5) } { st[\locks][\exciterType] = nil };
            if(0.20.coin) { st[\locks][\model] = rrand(0, 3) } { st[\locks][\model] = nil };
        };
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
        var path = ~plonkV54SoundDir +/+ (name ++ ".archive");
        ~plonkState.copy.writeArchive(path);
        ("Saved sound: " ++ path).postln;
    };

    ~plonkLoadSound = { |name="sound1"|
        var path = ~plonkV54SoundDir +/+ (name ++ ".archive");
        if(File.exists(path)) {
            ~plonkState = Object.readArchive(path).copy;
            ("Loaded sound: " ++ path).postln;
        }{
            ("Sound not found: " ++ path).warn;
        };
    };

    ~plonkSavePattern = { |name="pattern1"|
        var path = ~plonkV54PatternDir +/+ (name ++ ".archive");
        (seq: ~plonkSeq.copy.put(\task, nil), steps: ~plonkSteps.collect(_.deepCopy)).writeArchive(path);
        ("Saved pattern: " ++ path).postln;
    };

    ~plonkLoadPattern = { |name="pattern1"|
        var path = ~plonkV54PatternDir +/+ (name ++ ".archive");
        var obj;
        if(File.exists(path)) {
            obj = Object.readArchive(path);
            ~plonkSeq.putAll(obj[\seq].copy);
            ~plonkSeq[\task] = nil;
            ~plonkSteps = obj[\steps].collect(_.deepCopy);
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

    MIDIdef.noteOn(\plonkV54On, { |vel, note|
        ~plonkTrigger.((freq: note.midicps, velocity: vel / 127));
    });

    // --------------------------------------------------------
    // GUI
    // --------------------------------------------------------
    {
        var win, header, content;
        var pages = IdentityDictionary.new;
        var controls = IdentityDictionary.new;
        var stepButtons = Array.newClear(32);
        var stepIndicators = Array.newClear(32);
        var stepEditButtons = Array.newClear(32);
        var stepLabels = Array.newClear(32);
        var stepNoteMiniLabels = Array.newClear(32);
        var soundField, patternField, baseMidiLabel, stepNoteLabel;
        var lockStep = 0;
        var lockBoxes = IdentityDictionary.new;
        var lockEnableButtons = IdentityDictionary.new;
        var showPage, refreshControls, refreshPatternUI, refreshLockEditor;
        var makeButton, makePage, makeSlider, makeMenu;
        var modelNames = ["Bar", "Plate", "Bell", "Drum"];
        var exciterNames = ["Mallet", "HardPick", "Brush", "Scrape", "Burst", "ImpulseCluster"];

        ~plonkStepIndicators = stepIndicators;

        win = Window("Plonk-ish v5.4", Rect(60, 40, 1380, 940)).front;
        win.alwaysOnTop_(true);

        header = View(win, Rect(0, 0, 1380, 64));
        content = View(win, Rect(0, 66, 1380, 874));

        makeButton = { |parent, bounds, label, action|
            var b = Button(parent, bounds);
            b.states_([[label]]);
            b.action_({ action.value });
            b;
        };

        makePage = { |key|
            var v = View(content, Rect(0, 0, 1380, 874));
            v.visible_(false);
            pages[key] = v;
            v;
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

        refreshPatternUI = {
            32.do { |i|
                var st = ~plonkSteps[i];
                var isActive = i < ~plonkSeq[\steps];
                var noteName = ~plonkMidiToName.(~plonkStepMidiForIndex.(i));

                if(stepButtons[i].notNil) {
                    stepButtons[i].value_(st[\on]);
                    stepButtons[i].enabled_(isActive);
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
            };

            if(baseMidiLabel.notNil) {
                baseMidiLabel.string_(~plonkMidiToName.(~plonkSeq[\baseMidi]));
            };

            if(stepNoteLabel.notNil) {
                stepNoteLabel.string_(
                    "Resulting Note: " ++
                    ~plonkMidiToName.(~plonkStepMidiForIndex.(lockStep))
                );
            };
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
            if(lockEnableButtons[\on].notNil) { lockEnableButtons[\on].value_(st[\on]) };
            if(lockBoxes[\semi].notNil) { lockBoxes[\semi].value_(locks[\semi] ? 0) };

            ~plonkLockKeys.do { |k|
                var enKey = (k.asString ++ "_en").asSymbol;
                var v = locks[k];
                if(lockEnableButtons[enKey].notNil) {
                    if(k == \semi) {
                        lockEnableButtons[enKey].value_(1);
                    }{
                        lockEnableButtons[enKey].value_(v.notNil.asInteger);
                    };
                };
                if(lockBoxes[k].notNil) {
                    if(v.notNil) {
                        lockBoxes[k].value_(v);
                    }{
                        if(k != \semi) { lockBoxes[k].value_(0) };
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

        // header
        makeButton.(header, Rect(10, 16, 70, 28), "Main", { showPage.(\main) });
        makeButton.(header, Rect(90, 16, 70, 28), "Exciter", { showPage.(\exciter) });
        makeButton.(header, Rect(170, 16, 90, 28), "Resonator", { showPage.(\res) });
        makeButton.(header, Rect(270, 16, 100, 28), "Performance", { showPage.(\perf) });
        makeButton.(header, Rect(380, 16, 100, 28), "Pattern", { showPage.(\pattern) });
        makeButton.(header, Rect(490, 16, 80, 28), "Step", { showPage.(\step) });
        makeButton.(header, Rect(580, 16, 80, 28), "Audio", { showPage.(\audio) });

        makeButton.(header, Rect(680, 16, 80, 28), "Trigger", { ~plonkTrigger.(()) });
        makeButton.(header, Rect(770, 16, 55, 28), "Bar", { ~plonkModelPresets.(0); refreshControls.() });
        makeButton.(header, Rect(830, 16, 55, 28), "Plate", { ~plonkModelPresets.(1); refreshControls.() });
        makeButton.(header, Rect(890, 16, 55, 28), "Bell", { ~plonkModelPresets.(2); refreshControls.() });
        makeButton.(header, Rect(950, 16, 55, 28), "Drum", { ~plonkModelPresets.(3); refreshControls.() });

        makeButton.(header, Rect(1020, 16, 80, 28), "RandPat", {
            ~plonkRandomizePatternAndRefresh.();
            refreshPatternUI.();
            refreshLockEditor.();
        });

        StaticText(header, Rect(1120, 8, 50, 18)).string_("Sound");
        soundField = TextField(header, Rect(1170, 8, 100, 20)).string_("sound1");
        makeButton.(header, Rect(1275, 7, 44, 22), "Save", { ~plonkSaveSound.(soundField.string) });
        makeButton.(header, Rect(1323, 7, 44, 22), "Load", { ~plonkLoadSound.(soundField.string); refreshControls.() });

        StaticText(header, Rect(1120, 34, 50, 18)).string_("Patt");
        patternField = TextField(header, Rect(1170, 34, 100, 20)).string_("pattern1");
        makeButton.(header, Rect(1275, 33, 44, 22), "Save", { ~plonkSavePattern.(patternField.string) });
        makeButton.(header, Rect(1323, 33, 44, 22), "Load", {
            ~plonkLoadPattern.(patternField.string);
            refreshPatternUI.();
            refreshLockEditor.();
        });

        // main page
        {
            var v = makePage.(\main), y = 20;
            StaticText(v, Rect(20, 0, 500, 20)).string_("Main controls");
            makeMenu.(v, 20, y, "Model", \model, modelNames); y = y + 28;
            makeMenu.(v, 20, y, "Exciter", \exciterType, exciterNames); y = y + 28;
            makeSlider.(v, 20, y, "Freq", \freq, 40, 4000, \exp); y = y + 28;
            makeSlider.(v, 20, y, "Amp", \amp, 0.01, 0.6, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Pan", \pan, -1.0, 1.0, \lin); y = y + 28;
            makeSlider.(v, 20, y, "Velocity", \velocity, 0.0, 1.0, \lin); y = y + 28;
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
            var v = makePage.(\pattern), y = 20;
            StaticText(v, Rect(20, 0, 900, 20)).string_("Pattern + playhead (32-step UI)");

            StaticText(v, Rect(20, y, 44, 20)).string_("Tempo");
            NumberBox(v, Rect(70, y, 60, 20)).value_(~plonkSeq[\tempo]).action_({ |nb| ~plonkSeq[\tempo] = nb.value.clip(20, 300) });

            StaticText(v, Rect(140, y, 44, 20)).string_("Swing");
            NumberBox(v, Rect(190, y, 60, 20)).value_(~plonkSeq[\swing]).action_({ |nb| ~plonkSeq[\swing] = nb.value.clip(0, 0.49) });

            StaticText(v, Rect(260, y, 44, 20)).string_("Steps");
            NumberBox(v, Rect(310, y, 60, 20)).value_(~plonkSeq[\steps]).action_({ |nb|
                ~plonkSeq[\steps] = nb.value.asInteger.clip(1, 32);
                nb.value_(~plonkSeq[\steps]);
                refreshPatternUI.();
            });

            StaticText(v, Rect(390, y, 64, 20)).string_("Base Note");
            NumberBox(v, Rect(458, y, 60, 20)).value_(~plonkSeq[\baseMidi]).action_({ |nb|
                ~plonkSeq[\baseMidi] = nb.value.asInteger.clip(0, 127);
                nb.value_(~plonkSeq[\baseMidi]);

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
            });

            baseMidiLabel = StaticText(v, Rect(524, y, 70, 20));
            baseMidiLabel.string_(~plonkMidiToName.(~plonkSeq[\baseMidi]));

            makeButton.(v, Rect(610, y - 1, 60, 22), "Run", { ~plonkSeqStart.() });
            makeButton.(v, Rect(676, y - 1, 60, 22), "Stop", { ~plonkSeqStop.() });

            16.do { |i|
                var x = 20 + (i * 78);
                var topY = 90;

                stepIndicators[i] = StaticText(v, Rect(x + 18, topY, 24, 16));
                stepIndicators[i].string_(" ");

                stepLabels[i] = StaticText(v, Rect(x + 10, topY + 18, 40, 16));
                stepLabels[i].string_((i + 1).asString);

                stepButtons[i] = Button(v, Rect(x, topY + 40, 56, 24));
                stepButtons[i].states_([["-"], ["●"]]);
                stepButtons[i].value_(~plonkSteps[i][\on]);
                stepButtons[i].action_({ |bt| ~plonkSteps[i][\on] = bt.value });

                stepEditButtons[i] = makeButton.(v, Rect(x, topY + 70, 56, 20), "Edit", {
                    lockStep = i;
                    refreshLockEditor.();
                    showPage.(\step);
                });

                stepNoteMiniLabels[i] = StaticText(v, Rect(x + 2, topY + 95, 60, 14));
                stepNoteMiniLabels[i].string_(~plonkMidiToName.(~plonkStepMidiForIndex.(i)));
            };

            16.do { |j|
                var i = j + 16;
                var x = 20 + (j * 78);
                var topY = 230;

                stepIndicators[i] = StaticText(v, Rect(x + 18, topY, 24, 16));
                stepIndicators[i].string_(" ");

                stepLabels[i] = StaticText(v, Rect(x + 10, topY + 18, 40, 16));
                stepLabels[i].string_((i + 1).asString);

                stepButtons[i] = Button(v, Rect(x, topY + 40, 56, 24));
                stepButtons[i].states_([["-"], ["●"]]);
                stepButtons[i].value_(~plonkSteps[i][\on]);
                stepButtons[i].action_({ |bt| ~plonkSteps[i][\on] = bt.value });

                stepEditButtons[i] = makeButton.(v, Rect(x, topY + 70, 56, 20), "Edit", {
                    lockStep = i;
                    refreshLockEditor.();
                    showPage.(\step);
                });

                stepNoteMiniLabels[i] = StaticText(v, Rect(x + 2, topY + 95, 60, 14));
                stepNoteMiniLabels[i].string_(~plonkMidiToName.(~plonkStepMidiForIndex.(i)));
            };
        }.value;

        // step page
        {
            var v = makePage.(\step);
            var rowGap = 26;
            var addLockRow;

            StaticText(v, Rect(20, 10, 500, 20)).string_("Per-step editor");

            StaticText(v, Rect(20, 40, 80, 20)).string_("Step");
            lockBoxes[\stepNum] = NumberBox(v, Rect(100, 40, 50, 20)).value_(0).action_({ |nb|
                lockStep = nb.value.asInteger.clip(0, 31);
                nb.value_(lockStep);
                refreshLockEditor.();
            });

            stepNoteLabel = StaticText(v, Rect(900, 40, 220, 20));
            stepNoteLabel.string_("Resulting Note: " ++ ~plonkMidiToName.(~plonkSeq[\baseMidi]));

            lockEnableButtons[\on] = Button(v, Rect(170, 38, 60, 24)).states_([["Off"], ["On"]]).action_({ |bt|
                ~plonkSteps[lockStep][\on] = bt.value;
                refreshPatternUI.();
            });

            StaticText(v, Rect(250, 40, 44, 20)).string_("Prob");
            lockBoxes[\prob] = NumberBox(v, Rect(294, 40, 60, 20)).action_({ |nb| ~plonkSteps[lockStep][\prob] = nb.value.clip(0, 1) });

            StaticText(v, Rect(370, 40, 52, 20)).string_("Rat");
            lockBoxes[\ratchet] = NumberBox(v, Rect(420, 40, 60, 20)).action_({ |nb| ~plonkSteps[lockStep][\ratchet] = nb.value.asInteger.clip(1, 4) });

            StaticText(v, Rect(500, 40, 52, 20)).string_("Micro");
            lockBoxes[\micro] = NumberBox(v, Rect(552, 40, 60, 20)).action_({ |nb| ~plonkSteps[lockStep][\micro] = nb.value.clip(-0.49, 0.49) });

            StaticText(v, Rect(630, 40, 44, 20)).string_("Gate");
            lockBoxes[\gate] = NumberBox(v, Rect(674, 40, 60, 20)).action_({ |nb| ~plonkSteps[lockStep][\gate] = nb.value.clip(0.05, 1.25) });

            StaticText(v, Rect(750, 40, 54, 20)).string_("Accent");
            lockBoxes[\accent] = NumberBox(v, Rect(806, 40, 60, 20)).action_({ |nb| ~plonkSteps[lockStep][\accent] = nb.value.clip(0, 1) });

            addLockRow = { |x, y, label, key, min, max, isInt=false|
                StaticText(v, Rect(x, y, 96, 20)).string_(label);

                lockEnableButtons[(key.asString ++ "_en").asSymbol] = Button(v, Rect(x + 98, y - 2, 44, 24))
                    .states_([["Off"], ["On"]])
                    .action_({ |bt|
                        var val;
                        if(bt.value == 0) {
                            if(key != \semi) { ~plonkSteps[lockStep][\locks][key] = nil };
                        }{
                            val = lockBoxes[key].value;
                            if(isInt) { val = val.asInteger };
                            ~plonkSteps[lockStep][\locks][key] = val;
                        };
                        refreshPatternUI.();
                        if(key == \semi) { refreshLockEditor.() };
                    });

                lockBoxes[key] = NumberBox(v, Rect(x + 150, y, 80, 20)).action_({ |nb|
                    var val = nb.value.clip(min, max);
                    if(isInt) { val = val.asInteger };
                    nb.value_(val);

                    if((key == \semi) or: { lockEnableButtons[(key.asString ++ "_en").asSymbol].value == 1 }) {
                        ~plonkSteps[lockStep][\locks][key] = val;
                    };

                    if(key == \semi) {
                        if(stepNoteLabel.notNil) {
                            stepNoteLabel.string_(
                                "Resulting Note: " ++
                                ~plonkMidiToName.((~plonkSeq[\baseMidi] + val).clip(0, 127))
                            );
                        };
                    };

                    refreshPatternUI.();
                });
            };

            addLockRow.(20, 100 + (0 * rowGap), "Semi", \semi, -36, 36, true);
            addLockRow.(20, 100 + (1 * rowGap), "Velocity", \velocity, 0, 1);
            addLockRow.(20, 100 + (2 * rowGap), "Decay", \decay, 0.03, 6.0);
            addLockRow.(20, 100 + (3 * rowGap), "Brightness", \brightness, 0, 1);
            addLockRow.(20, 100 + (4 * rowGap), "Material", \material, 0, 1);
            addLockRow.(20, 100 + (5 * rowGap), "Inharm", \inharm, 0, 0.8);
            addLockRow.(20, 100 + (6 * rowGap), "Position", \position, 0.01, 0.49);
            addLockRow.(20, 100 + (7 * rowGap), "Body", \body, 0, 1);
            addLockRow.(20, 100 + (8 * rowGap), "Damp", \damp, 0, 1);
            addLockRow.(20, 100 + (9 * rowGap), "Drive", \drive, 0.7, 2.0);

            addLockRow.(420, 100 + (0 * rowGap), "Tone", \tone, 0, 1);
            addLockRow.(420, 100 + (1 * rowGap), "NoiseAmt", \noiseAmt, 0, 1.2);
            addLockRow.(420, 100 + (2 * rowGap), "ClickAmt", \clickAmt, 0, 2.0);
            addLockRow.(420, 100 + (3 * rowGap), "ExciterType", \exciterType, 0, 5, true);
            addLockRow.(420, 100 + (4 * rowGap), "Model", \model, 0, 3, true);
            addLockRow.(420, 100 + (5 * rowGap), "PitchEnvAmt", \pitchEnvAmt, 0, 0.4);
            addLockRow.(420, 100 + (6 * rowGap), "PitchEnvDec", \pitchEnvDecay, 0.005, 0.12);
            addLockRow.(420, 100 + (7 * rowGap), "Detune", \detune, 0, 0.02);
            addLockRow.(420, 100 + (8 * rowGap), "Spread", \spread, 0.2, 4.5);
            addLockRow.(420, 100 + (9 * rowGap), "Pan", \pan, -1, 1);

            makeButton.(v, Rect(20, 420, 90, 24), "Trig Step", {
                var st = ~plonkSteps[lockStep];
                if(st[\on] == 0) { st[\on] = 1 };
                ~plonkTrigger.(~plonkBuildStepArgs.(st));
                refreshPatternUI.();
            });

            makeButton.(v, Rect(120, 420, 90, 24), "Clear", {
                var oldSemi = ~plonkSteps[lockStep][\locks][\semi] ? 0;
                ~plonkSteps[lockStep][\locks] = ~makePlonkStep.()[\locks];
                ~plonkSteps[lockStep][\locks][\semi] = oldSemi;
                refreshLockEditor.();
                refreshPatternUI.();
            });

            makeButton.(v, Rect(220, 420, 90, 24), "Copy", {
                ~copiedPlonkStep = ~plonkSteps[lockStep].deepCopy;
            });

            makeButton.(v, Rect(320, 420, 90, 24), "Paste", {
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
            srBox = NumberBox(v, Rect(130, 130, 100, 20));
            srBox.value_(~plonkAudioState[\sampleRate]);
            srBox.action_({
                ~plonkAudioState[\sampleRate] = srBox.value.asInteger.clip(8000, 192000);
                srBox.value_(~plonkAudioState[\sampleRate]);
            });

            StaticText(v, Rect(20, 164, 100, 20)).string_("Out Channels");
            outChBox = NumberBox(v, Rect(130, 164, 100, 20));
            outChBox.value_(~plonkAudioState[\numOutChannels]);
            outChBox.action_({
                ~plonkAudioState[\numOutChannels] = outChBox.value.asInteger.clip(2, 128);
                outChBox.value_(~plonkAudioState[\numOutChannels]);
            });

            StaticText(v, Rect(20, 198, 100, 20)).string_("In Channels");
            inChBox = NumberBox(v, Rect(130, 198, 100, 20));
            inChBox.value_(~plonkAudioState[\numInChannels]);
            inChBox.action_({
                ~plonkAudioState[\numInChannels] = inChBox.value.asInteger.clip(0, 128);
                inChBox.value_(~plonkAudioState[\numInChannels]);
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
        refreshPatternUI.();
        refreshLockEditor.();
        ~plonkRefreshAudioMenus.();
        showPage.(\main);

        win.onClose_({
            ~plonkSeqStop.();
            MIDIdef.noteOn(\plonkV54On).free;
            ~plonkVoices.do { |entry| entry[\synth].set(\gate, 0) };
            ~plonkVoices.clear;
        });
    }.defer;

});
)
