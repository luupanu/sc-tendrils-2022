// TO-DO:
// - iskuja supertiibet, delayed by ~50ms, chorused?
// - laulava kulho sinne tänne
// - ranni_splursk tais olla kova
// - TULVA joka menee kaiken yli?
// - BASS välillä pois

(
//cleanup
Pbindef.all.do(_.clear);
Pdef.all.do(_.clear);
~wt_buf.do(_.free);
~buffers.do(_.free);
~st_buffers.do(_.free);
t.stop;

s.options.numWireBufs_(512);

//initialization
s = Server.local;
t = TempoClock(54/60).permanent_(true);
d = TempoClock(54/60);
s.newBusAllocators;

/////////////////////////////// BUSES /////////////////////////////
~del_bus = Bus.audio(s, 2);
~conv0_bus = Bus.audio(s, 2);
~conv2_bus = Bus.audio(s, 2);

~heart_amp_ctrl = Bus.control(s, 1);

~synth_amp_ctrl = Bus.control(s, 1);
~synth_reverb_ctrl = Bus.control(s, 1);
~synth_delay_ctrl = Bus.control(s, 1);

~bass1_amp_ctrl = Bus.control(s, 1);
~bass2_amp_ctrl = Bus.control(s, 1);
~bass_reverb_ctrl = Bus.control(s, 1);
~bass_delay_ctrl = Bus.control(s, 1);

~lock_t = 0;

~touchdesigner = NetAddr("localhost", 57121);

s.waitForBoot({
    //////////////////////////////////// VARIABLES ////////////////////////////////////
    var nrows = 36;
    var ncols = 42;

    /////////////////////////////// GROUPS /////////////////////////////
    ~ctrl_grp = Group.new;
    ~synth_grp = Group.after(~ctrl_grp);
    ~fx_grp = Group.after(~synth_grp);

    //////////////////////////////////// FUNCTIONS ////////////////////////////////////
    ~index_2d = { |i, ncols| [(i / ncols).asInteger, i % ncols] };

    /////////////////////////////// WAVETABLE SIGNALS /////////////////////////////
    // From Eli Fieldsteel: https://sccode.org/1-5bF
    ~wt_sig = 10.collect({
        arg i;

        //random number of envelope segments
        var numSegs = i.linexp(0,9,4,40).round;

        Env(
            //env always begins and ends with zero
            //inner points are random from -1.0 to 1.0
            [0]++({1.0.rand}.dup(numSegs-1) * [1,-1]).scramble++[0],

            //greater segment duration variety in higher-index wavetables
            {exprand(1, i.linexp(0,9,1,50))}.dup(numSegs),

            //low-index wavetables tend to be sinusoidal
            //high index wavetables tend to have sharp angles and corners
            {[\sine,0,exprand(1,20) * [1,-1].choose].wchoose([9-i,3,i].normalizeSum)}.dup(numSegs)
        ).asSignal(2048);
    });

    /////////////////////////////// WAVETABLE BUFFERS /////////////////////////////
    ~wt_buf = Buffer.allocConsecutive(10, s, 4096, 1, { |buf, i|
        buf.setnMsg(0, ~wt_sig[i].asWavetable);
    });

    /////////////////////////////// SYNTHDEFS /////////////////////////////
    SynthDef(\rampControl, { |fadeTime|

    }).add;

    SynthDef(\convolution, { |in, out|
        var signal = In.ar(in, 1);
        Out.ar(out, VSTPlugin.ar(signal!2, 2, id: \convolution));
    }).add;

    SynthDef(\delay, { |in, out, del_l=0.371, del_r=0.668, decay_l=1.0, decay_r=1.0, amp=1, rq=1, lagTime=0.5, panrate=1|
        var delayL, delayR, panned;
        var sig = In.ar(in, 2);

        delayL = CombC.ar(sig[0], 5, Lag3.kr(del_l, lagTime), Lag3.kr(decay_l, lagTime));
        delayR = CombC.ar(sig[1], 5, Lag3.kr(del_r, lagTime), Lag3.kr(decay_r, lagTime));

        delayL = HPF.ar(delayL, 600);
        delayR = HPF.ar(delayL, 600);

        delayL = BPF.ar(delayL, 1400, rq);
        delayR = BPF.ar(delayR, 1400, rq);

        panned = PanAz.ar(
            numChans: 4,
            in: [delayL, delayR],
            pos: LFNoise2.ar(panrate),
            level: amp,
            width: 2,
            orientation: 0,
        );

        Out.ar(out, panned);
    }).add;

    SynthDef(\hihat, {|out = 0, amp = 0.5, att = 0.01, rel = 0.2, ffreq = 6000, pan = 0, delaysend=(-60), rev0send=(-60), rev2send=(-60)|
        var env, sig;

        env = Env.perc(att, rel, amp).kr(doneAction: 2);
        sig = WhiteNoise.ar;
        sig = HPF.ar(sig, ffreq, env);

        Out.ar(out, Pan2.ar(sig, pan, amp));
        Out.ar(~del_bus, sig * delaysend.dbamp);
        Out.ar(~conv0_bus, sig * rev0send.dbamp);
        Out.ar(~conv2_bus, sig * rev2send.dbamp);
    }).add;

    SynthDef(\hitsMono, { |bufnum, out, rate=1, lpfreq=20000, hpfreq=100, amp, gate=1, delaysend=(-60), rev0send=(-60), rev2send=(-60), time, panrate=1, t_trig|
        var buf, env, sig, frames, duration, panned;

        // send color to touchdesigner
        SendReply.kr(t_trig, "/sendColor", [rrand(-1.0, -0.5), rrand(4.0, 5.0)]);

        frames = BufFrames.kr(bufnum);
        duration = frames/rate.abs/s.sampleRate;

        buf = PlayBuf.ar(1, bufnum, LFNoise2.kr(0.02, mul: 0.051315789473684204, add: 1.0013157894736842) * rate * BufRateScale.kr(bufnum), loop: 0);
        env = EnvGen.kr(Env.linen(sustainTime: time), gate, doneAction: 2);
        sig = LPF.ar(buf * env, lpfreq);
        sig = HPF.ar(sig, hpfreq);
        sig = (rate.abs<1)*(rate.abs)*sig + sig;

        // [rate, lpfreq, time, rev0send].poll(1).postln;

        panned = PanAz.ar(
            numChans: 4,
            in: sig,
            pos: LFNoise2.ar(panrate),
            level: amp,
            width: 2,
            orientation: 0,
        );

        Out.ar(out, panned);
        Out.ar(~del_bus, panned[2..3] * delaysend.dbamp);
        Out.ar(~conv0_bus, panned[0..1] * rev0send.dbamp);
        Out.ar(~conv2_bus, panned[2..3] * rev2send.dbamp);
    }).add;

    SynthDef(\looperMono, { |bufnum, out, lagTime=2, rate=1, amp, lpfreq=20000, hpfreq=10, delaysend=(-60), rev0send=(-60), rev2send=(-60)|
        var buf = BufRd.ar(1, bufnum, Phasor.ar(0, rate, 0, BufFrames.kr(bufnum), 0), 1, 4);
        var lagAmp = Lag3.ar(K2A.ar(amp), lagTime);

        var sig = LPF.ar(buf * lagAmp, lpfreq);
        sig = HPF.ar(sig, hpfreq);

        // lagAmp.scope;

        Out.ar(out, sig!2);
        Out.ar(~del_bus, (sig!2) * delaysend.dbamp);
        Out.ar(~conv0_bus, (sig!2) * rev0send.dbamp);
        Out.ar(~conv2_bus, (sig!2) * rev2send.dbamp);
    }).add;

    SynthDef(\looperStereo, { |bufnum, out, lagTime=2, rate=1, amp, lpfreq=20000, hpfreq=10, delaysend=(-60), rev0send=(-60), rev2send=(-60), panrate=0.1, panphase=0, pandirection=1|
        var buf = BufRd.ar(2, bufnum, Phasor.ar(0, rate, 0, BufFrames.kr(bufnum), 0), 1, 4);
        var lagAmp = Lag3.ar(K2A.ar(amp), lagTime);
        var panned;
        var sig = LPF.ar(buf * lagAmp, lpfreq);
        sig = HPF.ar(sig, hpfreq);

        panned = PanAz.ar(
            numChans: 4,
            in: sig[0],
            pos: pandirection * (LFTri.ar(panrate) + panphase),
            level: amp,
            width: 2,
            orientation: 0,
        );

        Out.ar(out, panned);
        Out.ar(~del_bus, sig * delaysend.dbamp);
        Out.ar(~conv0_bus, sig * rev0send.dbamp);
        Out.ar(~conv2_bus, sig * rev2send.dbamp);
    }).add;

     SynthDef(\heartStereo, { |bufnum, out, lagTime=2, rate=1, amp, lpfreq=20000, hpfreq=10, delaysend=(-60), rev0send=(-60), rev2send=(-60), heartOnTime=20, heartOffTime=20, fadeTime=2|
        var buf = BufRd.ar(2, bufnum, Phasor.ar(0, Lag3.kr(rate, 5), 0, BufFrames.kr(bufnum), 0), 1, 4);
        var lagAmp = Lag3.ar(K2A.ar(amp), lagTime);
        var env, sig;

        env = EnvGen.ar(Env.circle([0, 1, 1, 0, 0], [fadeTime, heartOnTime, fadeTime, heartOffTime], [4, 0, -4, 0]));
        sig = LPF.ar(buf * lagAmp, lpfreq);
        sig = HPF.ar(sig, hpfreq);
        sig = sig * env;

        //lagAmp.scope;

        Out.ar(out, sig);
        Out.ar(~del_bus, sig * delaysend.dbamp);
        Out.ar(~conv0_bus, sig * rev0send.dbamp);
        Out.ar(~conv2_bus, sig * rev2send.dbamp);
    }).add;

    SynthDef(\vosc1, { |out, buf=0, numBufs=10, bufpos, freq, gate=1, pan=0, panSpread=0.5, amp=0.2, detune=0.2, ffreq=4000, rq=1, delaysend=(-60), rev0send=(-60), rev2send=(-60), att=0.12, dec=0.6, sus=0.66, rel=0.6, peak=1|
        var sig, env, filter, detuneCtrl;

        // env = EnvGen.ar(Env.adsr(att, dec, sus, rel, peak), gate, doneAction: 2);
        env = EnvGen.ar(Env.perc(att, rel), gate, doneAction: 2);
        detuneCtrl = LFNoise1.kr(0.1!8).bipolar(detune).midiratio;

        sig = Saw.ar(freq/2 * detuneCtrl, mul: 0.8)!4;
        sig = sig + VOsc.ar(buf+Lag3.kr(bufpos), freq * detuneCtrl, {Rand(0,2pi)}!8);
        sig = Splay.ar(sig, panSpread);
        sig = LeakDC.ar(sig);
        sig = Balance2.ar(sig[0], sig[1], pan, amp);

        sig = sig * env;
        filter = RLPF.ar(sig, ffreq, rq);

        // bufpos.poll.postln;

        // Out.ar(out, filter);
        Out.ar(~del_bus, filter * delaysend.dbamp);
        Out.ar(~conv0_bus, filter * rev0send.dbamp);
        Out.ar(~conv2_bus, filter * rev2send.dbamp);
    }).add;

    SynthDef(\vosc2, { |out, buf=0, numBufs=10, bufpos, freq, gate=1, pan=0, panSpread=0.5, amp=0.2, detune=0.2, lpfreq=500, rq=0.25, delaysend=(-60), rev0send=(-60), rev2send=(-60), att=0.12, dec=0.6, sus=0.66, rel=0.6, peak=1|
        var sig, env, detuneCtrl, filter1, filter2, filter3;

        // env = EnvGen.ar(Env.adsr(att, dec, sus, rel, peak), gate, doneAction: 2);
        env = EnvGen.ar(Env.perc(att, rel), gate, doneAction: 2);
        detuneCtrl = LFNoise1.kr(0.1!8).bipolar(detune).midiratio;

        sig = Saw.ar(freq/2 * detuneCtrl, mul: 0.8)!4;
        sig = sig + VOsc.ar(buf+Lag3.kr(bufpos), freq * detuneCtrl, {Rand(0,2pi)}!8);
        sig = Splay.ar(sig, panSpread);
        sig = LeakDC.ar(sig);
        sig = Balance2.ar(sig[0], sig[1], pan, amp);

        sig = sig * env;

        filter1 = DFM1.ar(sig, 68, 0.9);
        filter2 = DFM1.ar(sig, 139, 0.6); // RLPF.ar(sig, lpfreq, rq);
        filter3 = DFM1.ar(sig, 210, 0.8);

        sig = (filter1*0.75) + filter2 + filter3 + sig;

        Out.ar(out, sig!4);

        // Out.ar(out, ((sig + filter)*0.3)!4);


        /*Out.ar(~del_bus, filter * delaysend.dbamp);
        Out.ar(~conv0_bus, filter * rev0send.dbamp);
        Out.ar(~conv2_bus, filter * rev2send.dbamp);*/
    }).add;

    SynthDef(\bass, { arg out=0, freq=440, amp=0.1, pan=0, gate=1;
			var z;
			z = LPF.ar(
				Mix.new(VarSaw.ar(freq + [0, Rand(-0.4,0.0), Rand(0.0,0.4)], 0, 0.3, 0.3)),
				XLine.kr(Rand(4000,5000), Rand(2500,3200), 1)
			) * Linen.kr(gate, 0.01, 0.7, 0.3, 2);
        OffsetOut.ar(out, (0*z*amp)!4);
		}).add;

    s.sync;

    //////////////////////////////////// BUFFERS ////////////////////////////////////
    ~buffers = Dictionary();
    SoundFile.collectIntoBuffers(thisProcess.nowExecutingPath.dirname +/+ "sounds/*", s).do({ |buf| ~buffers.put(PathName(buf.path).fileNameWithoutExtension.asString, buf) });

    ~st_buffers = SoundFile.collectIntoBuffers(thisProcess.nowExecutingPath.dirname +/+ "sounds/supertiibet/*", s);

    s.sync;

    ///////////////////////////////////////// VSTS /////////////////////////////////////////
    ~convolution0 = VSTPluginController(Synth(\convolution, [\in, ~conv0_bus, \out, 0], ~fx_grp), id: \convolution);
    ~convolution0.open(
        "Convology XT.vst3",
        editor: true,
        verbose: true,
        action: {
            ~convolution0.loadPreset("nycsports");
        },
    );

    ~convolution2 = VSTPluginController(Synth(\convolution, [\in, ~conv2_bus, \out, 2], ~fx_grp), id: \convolution);
    ~convolution2.open(
        "Convology XT.vst3",
        editor: true,
        verbose: true,
        action: {
            ~convolution2.loadPreset("hamilton");
        },
    );

    //////////////////////////////////// SYNTHS ////////////////////////////////////
    ~heart = Synth(\heartStereo, [\bufnum, ~buffers["heart2"], \out, 0, \amp, 0.05], ~synth_grp);
    ~pisara = Synth(\looperStereo, [\bufnum, ~buffers["pisaroita"], \out, 0, \amp, 0.001, \hpfreq, 500, \panrate, 0.3, \panphase, 1, \pandirection, -1], ~synth_grp);
    ~ranni_korkea = Synth(\looperStereo, [\bufnum, ~buffers["ranni_korkea_1"], \out, 0, \amp, 0.001, \panphase, 0.5, \rate, 2, \pandirection, -1], ~synth_grp);
    ~aaltoja = Synth(\looperStereo, [\bufnum, ~buffers["aaltoja"], \out, 0, \amp, 0.001, \hpfreq, 125, \panrate, 0.15], ~synth_grp);
    ~jaapuikko_ranni = Synth(\looperStereo, [\bufnum, ~buffers["jaapuikko_ranni"], \out, 0, \amp, 0.1, \hpfreq, 150, \panrate, 0.08, \pandirection, -1], ~synth_grp);
    ~radio_aaltoa = Synth(\looperStereo, [\bufnum, ~buffers["hyvaa_radio_aaltoa"], \out, 0, \amp, 0.1, \hpfreq, 150], ~synth_grp);
    ~supertiibet = Synth(\hitsMono, [\out, 0, \amp, 0.75, \rev0send, -20, \rev2send, -12 ], ~synth_grp);

    ~delay = Synth(\delay, [\in, ~del_bus, \out, 0, \amp, 1.2], ~fx_grp);
    //~vosc = Synth(\vosc, [\amp, 0, \bufpos, 8.8, \lffreq, 500], ~synth_grp);

    //////////////////////////////////// OSCDEFS ////////////////////////////////////
    OSCdef(\sendColor, { |msg|
        var color = msg[3];
        var rampTime = msg[4];

        ~touchdesigner.sendMsg("/color", color, rampTime);
        [color, rampTime].postln;

    }, "/sendColor");

    OSCdef(\kinect, { |msg|
        var kinect_data = Matrix.withFlatArray(nrows, ncols, msg[1..]) * (-0.3030303030303030) + 1;
        var mean = kinect_data.sum / (kinect_data.rows*kinect_data.cols);
        var maxIndex2D = ~index_2d.(kinect_data.flat.maxIndex, ncols);
        var maxVal = kinect_data.at(maxIndex2D[0], maxIndex2D[1]);

        if ((~lock_t == 0) and: (mean >= 0.47), {
            ~lock_t = 1;
            ~bassTranspose = [-8, -6, -3, 0].choose;
            // ~chosenFreq = [72, 76, 79, 82, 84, 86, 88, 89, 90].wchoose([0.145, 0.145, 0.1175, 0.1175, 0.145, 0.09, 0.09, 0.09, 0.06]).midicps;
            // ~chosenFreq = [24, 28, 31, 34, 36, 38, 40, 41, 42].wchoose([0.145, 0.145, 0.1175, 0.1175, 0.145, 0.09, 0.09, 0.09, 0.06]).midicps; // exprand(23, 40).midicps; // TO-DO: should this be rounded to integer?
            // ~chosenFreq.postln;
        }, {
            if (mean < 0.47, {
                ~lock_t = 0;
                ~bassTranspose = 0;
            });
        });

        d.tempo = mean.linexp(0.465, 0.5, 54/60, 81/60);

        Pdefn(\ctranspose, ~bassTranspose);

        ~heart.set(
            \amp, mean.linexp(0.45, 0.5, 0.05, 0.4),
            \rate, mean.lincurve(0.465, 0.5, 0.75, 2.4, 2),
            \rev2Send, mean.linexp(0.465, 0.5, -60, -12),
            \lpreq, mean.linexp(0.465, 0.5, 400, 200),
        );

        ~pisara.set(
            \amp, mean.lincurve(0.465, 0.5, 0.001, 1.2, 4),
            \lpreq, mean.linexp(0.465, 0.5, 500, 10000),
        );

        ~aaltoja.set(
            \amp, mean.linexp(0.465, 0.5, 0.001, 3),
            \rate, mean.lincurve(0.465, 0.5, 0.75, 1.75, 2),
        );

        ~jaapuikko_ranni.set(
            \amp, mean.linexp(0.465, 0.5, 1, 0.001),
            \lpfreq, mean.linexp(0.465, 0.5, 250, 2000),
        );

        ~radio_aaltoa.set(
            \amp, mean.linexp(0.465, 0.5, 0.1, 1.5),
            \lpfreq, mean.linexp(0.465, 0.5, 20000, 2500),
        );

        ~ranni_korkea.set(
            \amp, mean.linexp(0.465, 0.5, 0.001, 1),
            \hpfreq, mean.linlin(0.465, 0.5, 200, 200),
        );

        // ~synth_amp_ctrl.value = mean.lincurve(0.465, 0.5, 0.001, 0.07, 2);
        ~synth_amp_ctrl.value = mean.lincurve(0.465, 0.5, 0.001, 0.04, 2);
        ~synth_reverb_ctrl.value = mean.linexp(0.465, 0.5, -22, -16);
        ~synth_delay_ctrl.value = mean.linexp(0.465, 0.5, -12, -6);

        //~bass1_amp_ctrl.value = mean.lincurve(0.465, 0.5, 0.001, 0.05, 2);
        ~bass1_amp_ctrl.value = mean.lincurve(0.465, 0.5, 0.001, 0.03, 2);
        //~bass2_amp_ctrl.value = mean.lincurve(0.465, 0.5, 0.0005, 0.015, 2);
        ~bass2_amp_ctrl.value = mean.lincurve(0.465, 0.5, 0.0005, 0.01, 2);
        ~bass_reverb_ctrl.value = mean.lincurve(0.465, 0.5, -12, -6, 2);
        ~bass_delay_ctrl.value = mean.linexp(0.465, 0.5, -12, -6);

        /*
        ~vosc.set(
            \amp, mean.lincurve(0.465, 0.5, 0, 0.03, 2),
            \att, rrand(0.01, 0.5),
            // \att, rrand(7.0, 9.0),
            // \att, mean.lincurve(0.465, 0.5, 0, 4, 2),
            \dec, mean.lincurve(0.465, 0.5, 5, 8, 2),
            \freq, ~chosenFreq,
            // \bufpos, mean.linexp(0.465, 0.5, 0.01, 4),
            \delaysend, mean.linexp(0.465, 0.5, -60, -3),
            \rev2send, mean.linlin(0.465, 0.5, -60, -12),
            \rev0send, mean.linlin(0.465, 0.5, -60, -12),
        );*/

        ~delay.set(
            \del_l, mean.linexp(0.465, 0.5, 0.371, 2),
            \del_r, mean.linexp(0.465, 0.5, 0.668, 4),
            \decay_l, mean.linexp(0.465, 0.5, 4, 2),
            \decay_r, mean.linexp(0.465, 0.5, 2, 1),
            \rq, mean.linexp(0.465, 0.5, 0.5, 4),
            \lagTime, 0.1,
            \panrate, 0.5, //mean.linexp(0.465, 0.5, 2, 0.05),
        );
    }, "/l0");

    //////////////////////////////////// PATTERNS ////////////////////////////////////
    ~supertiibet_rate = Pgauss(1, 1, inf);

    Pbindef(\supertiibet,
        \instrument, \hitsMono,
        \bufnum, Pxrand((~st_buffers[0].bufnum..~st_buffers.wrapAt(-1).bufnum), inf),
        \dur, Prand([5, 8, 10], inf),
        \delta, Pwrand([12, 24, 36, 48], [0.2, 0.3, 0.4, 0.1], inf),
        \lpfreq, Pbeta(250, 2500, 5, 10, inf), // Pgauss(500, 100, inf),
        \rev0send, Pgauss(-6, 1, inf),
        \time, Pgauss(10, 2, inf),
        \rate, ~supertiibet_rate,
        \panrate, Pbeta(0.1, 3, 3, 10, inf),
        \t_trig, 1,
        \callback, { ~send_color.(~supertiibet_rate.asStream.next); },
    );

    Pbindef(\leadSynth,
        \instrument, \vosc1,
        \dur, Pwrand([
            Pseq([1/16, 1/16, 1/16], 1),
            Pseq([1/8, 1/8, 1/8, 1/8], 1),
            Pseq([1/8, 1/8, 1/8], 1),
            Pseq([1/4, 1/4], 1),
        ], [1, 4, 6, 3].normalizeSum, inf),
        \stretch, 2,
        \octave, Pwrand((1..6), [0.05, 0.1, 0.2125, 0.2125, 0.2125, 0.2125], inf),
        \amp, ~synth_amp_ctrl.asMap,
        \att, Pbeta(0.03, 0.1, 10, 10, inf),
        \rel, Pbeta(0.1, 0.2, 10, 10, inf),
        \degree, Pwhite(10, 20, inf),
        \scale, Scale.phrygian,
        \rev0send, ~synth_reverb_ctrl.asMap,
        \rev2send, ~synth_reverb_ctrl.asMap,
        \delaysend, ~synth_delay_ctrl.asMap,
    );

    Pbindef(\bassSynth1,
        \instrument, \default,
        \dur, Pwrand([
            Pseq([1/8, 1/8, 1/8, 1/8], 1),
            Pseq([Rest(1/8), 1/8, 1/8, 1/8], 1),
        ], [4, 1].normalizeSum, inf),
        \stretch, 3,
        \octave,  Pwrand((3..5), [0.8, 0.2, 0.1], inf),
        \amp, ~bass1_amp_ctrl.asMap,
        \att, Pbeta(0.5, 2, 10, 10, inf),
        \rel, 2,
        \degree, 1,
        \ctranspose, Pdefn(\ctranspose), // ~bass_transpose_ctrl.asMap,
        \bufpos, 4,
        \scale, Scale.phrygian,
    );

    Pbindef(\bassSynth2,
        \instrument, \vosc2,
        \dur, Pwrand([
            Pseq([1/8, 1/8, 1/8, 1/8], 1),
            Pseq([Rest(1/8), 1/8, 1/8, 1/8], 1),
        ], [4, 1].normalizeSum, inf),
        \stretch, 3,
        \octave,  Pwrand((4..6), [0.8, 0.2, 0.1], inf),
        \amp, ~bass2_amp_ctrl.asMap,
        \att, 0.01, // Pbeta(0.5, 2, 10, 10, inf),
        \rel, 4,
        \degree, 1,
        \ctranspose, Pdefn(\ctranspose), // ~bass_transpose_ctrl.asMap,
        \bufpos, 0,
        \scale, Scale.phrygian,
        \rev0send, ~bass_reverb_ctrl.asMap,
        \rev2send, ~bass_reverb_ctrl.asMap,
        \delaysend, ~bass_delay_ctrl.asMap,
    );

    Pbindef(\bassSynth1).play(t, quant: 1);
    Pbindef(\bassSynth2).play(t, quant: 1);
    Pbindef(\leadSynth).play(d, quant: 1);
    Pbindef(\supertiibet).play(t);

    ////////////////////////////////////// ROUTINES ////////////////////////////////
    fork {
        loop {
            ~heart.set(\heartOnTime, rrand(20.0, 30.0));
            ~heart.set(\heartOffTime, rrand(20.0, 30.0));
            60.0.yield;
        };
    };

})

)

~convolution0.editor;
~convolution2.editor;