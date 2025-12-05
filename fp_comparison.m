clc;
clear;
close all;

% System params
p.fs = 30000;
p.bin_ms = 50;
p.s_per_bin = p.bin_ms * (p.fs/1000);
p.frac = 12;
p.scale = 2^p.frac;

% Filter coefficients
fc = 250;
wc = tan(pi * fc / p.fs);
norm = 1 + sqrt(2)*wc + wc^2;
b = [1, -2, 1] / norm;
a = [1, (2*(wc^2 - 1))/norm, (1 - sqrt(2)*wc + wc^2)/norm];
p.b_int = round(b * p.scale);
p.a_int = round(a * p.scale);

% Data generation
T = 50;
N = T * p.fs;

% Initialize state
lfsr = uint32(hex2dec('ACE12345'));
lfp_idx = 0;
lfp_timer = 0;
spike_idx = 0;
spike_lut = [200, 500, -2000, -10000, -20000, -15000, -5000, 3000, 5000, 3000, 1000, 500, 0];
raw_int = zeros(1, N);

% Data generation
for k = 1:N
    % 32b LFSR for RNG
    b31 = bitget(lfsr, 32);
    b21 = bitget(lfsr, 22);
    b1 = bitget(lfsr, 2);
    b0 = bitget(lfsr, 1);
    feedback = bitxor(bitxor(bitxor(b31, b21), b1), b0);
    lfsr = bitshift(bitand(lfsr, 2147483647), 1) + feedback;

    % AWGN generation
    s1 = double(bitand(lfsr, 31)) - 16;
    s2 = double(bitand(bitshift(lfsr, -5), 31)) - 16;
    s3 = double(bitand(bitshift(lfsr, -10), 31)) - 16;
    s4 = double(bitand(bitshift(lfsr, -15), 31)) - 16;
    noise_val = (s1 + s2 + s3 + s4) * 16;

    % LFP generation
    if lfp_idx == 0, lfp_val = 0;
    elseif lfp_idx == 8, lfp_val = 707;
    elseif lfp_idx == 16, lfp_val = 1000;
    elseif lfp_idx == 24, lfp_val = 707;
    elseif lfp_idx == 32, lfp_val = 0;
    elseif lfp_idx == 40, lfp_val = -707;
    elseif lfp_idx == 48, lfp_val = -1000;
    elseif lfp_idx == 56, lfp_val = -707;
    else
        if lfp_idx < 16, lfp_val = 500;
        elseif lfp_idx < 32, lfp_val = 500;
        elseif lfp_idx < 48, lfp_val = -500;
        else, lfp_val = -500;
        end
    end

    % LFP timer
    lfp_timer = lfp_timer + 1;
    if lfp_timer > 255
        lfp_timer = 0;
        lfp_idx = lfp_idx + 1;
        if lfp_idx > 63, lfp_idx = 0;
        end
    end

    % Spike playback
    spike_val = 0;
    if spike_idx == 0
        % Trigger every 1500 samples
        if (bitand(lfsr, 65535) < 54) && (k > 1500)
            spike_idx = 1;
        end
    else
        if spike_idx <= length(spike_lut)
            spike_val = spike_lut(spike_idx);
        end
        spike_idx = spike_idx + 1;
        if spike_idx > 13, spike_idx = 0;
        end
    end

    % Input signal
    raw_int(k) = lfp_val + spike_val + noise_val;
end

% Float input generation
d.raw_int = raw_int;
d.raw_float = double(raw_int) / p.scale;

% Export for FPGA testbench
fileID = fopen('test_vector.txt', 'w');
fprintf(fileID, '%d\n', d.raw_int);
fclose(fileID);

% Decoder params
p.M1 = 0.95;
p.M2 = 0.20;
p.M1_int = round(p.M1 * p.scale);
p.M2_int = round(p.M2 * p.scale);
p.max_v = 5.0 * p.scale;

% State init
pipe_float.filt = [0 0];
pipe_float.timer = 0;
pipe_float.vel = 0;
pipe_float.bin = 0;
pipe_float.thresh_acc = 0;

pipe_fix.filt = [0 0];
pipe_fix.timer = 0;
pipe_fix.vel = 0;
pipe_fix.bin = 0;

% Adaptive threshold params
K = 14;
thresh_fix_acc = 0;
WARMUP_LIMIT = 5 * p.fs;
warmup_cnt = 0;

% Store for plotting
history_i_vel = [];
history_f_vel = [];
history_thresh_fix = zeros(1, N);
history_filt_fix = zeros(1, N);

bin_clk = 0;

% Pipeline
for k = 1:N
    % Filter
    [f_val, pipe_float.filt] = mod_filt_float(d.raw_float(k), pipe_float.filt, b, a);
    [i_val, pipe_fix.filt] = mod_filt_int(d.raw_int(k), pipe_fix.filt, p.b_int, p.a_int, p.frac);

    % Normalize and store filtered fixed value for plotting
    history_filt_fix(k) = double(i_val) / p.scale;

    % Adaptive threshold fixed
    if i_val == -32768, abs_val_i = 32767;
    else, abs_val_i = abs(i_val);
    end

    term_leak_i = floor(thresh_fix_acc / (2^K));
    thresh_fix_acc = thresh_fix_acc - term_leak_i + abs_val_i;
    mav_i = floor(thresh_fix_acc / (2^K));
    thresh_fix_curr = -floor((mav_i * 45) / 8);

    % Normalize and store threshold for plotting
    history_thresh_fix(k) = double(thresh_fix_curr) / p.scale;

    % Adaptive threshold float
    abs_val_f = abs(f_val * p.scale);
    pipe_float.thresh_acc = pipe_float.thresh_acc - floor(pipe_float.thresh_acc/(2^K)) + abs_val_f;
    mav_f = floor(pipe_float.thresh_acc / (2^K));
    thresh_float_curr = (-floor((mav_f * 45) / 8)) / p.scale;

    % Spike detection
    [f_spike, pipe_float.timer] = mod_det_float(f_val, thresh_float_curr, pipe_float.timer);
    [i_spike, pipe_fix.timer] = mod_det_int(i_val, thresh_fix_curr, pipe_fix.timer);

    % Warmup
    if warmup_cnt < WARMUP_LIMIT
        f_spike = 0;
        i_spike = 0;
        warmup_cnt = warmup_cnt + 1;
    end

    % Binning
    pipe_float.bin = pipe_float.bin + f_spike;
    pipe_fix.bin = pipe_fix.bin + i_spike;

    bin_clk = bin_clk + 1;

    % Velocity update
    if bin_clk >= p.s_per_bin
        pipe_fix.vel = mod_dec_int(pipe_fix.bin, pipe_fix.vel, p.M1_int, p.M2_int, p.frac, p.max_v);
        pipe_float.vel = pipe_float.vel * p.M1 + pipe_float.bin * p.M2;

        history_i_vel = [history_i_vel, double(pipe_fix.vel)/p.scale];
        history_f_vel = [history_f_vel, pipe_float.vel];

        pipe_fix.bin = 0;
        pipe_float.bin = 0;
        bin_clk = 0;
    end
end

% Velocity decoder output plot
subplot(3,1,1);
t_axis = (1:length(history_i_vel)) * p.bin_ms / 1000;
plot(t_axis, history_i_vel);
hold on;
plot(t_axis, history_f_vel, '--');
legend('Fixed Point', 'Floating Point', 'Location', 'best');
title('Velocity Output');
ylabel('Velocity');
grid on;

% Quantization error plot
subplot(3,1,2);
plot(t_axis, history_f_vel - history_i_vel);
title('Quantization Error');
ylabel('Error');
grid on;

% Adaptive threshold correctness plot
subplot(3,1,3);
t_full = (1:N) / p.fs;
plot(t_full, history_filt_fix);
hold on;
plot(t_full, history_thresh_fix);

title('Adaptive Threshold');
legend('Filtered Signal', 'Threshold');
xlabel('Time (s)');
ylabel('Amplitude');
grid on;
xlim([0, T]);

% Helpers
function [y, s_next] = mod_filt_float(x, s, b, a)
y = b(1)*x + s(1);
s_next = [b(2)*x + s(2) - a(2)*y, b(3)*x - a(3)*y];
end
function [spk, t_next] = mod_det_float(x, th, t)
spk = 0;
t_next = t;
if t_next > 0, t_next = t_next - 1;
elseif x < th, spk = 1;
    t_next = 20;
end
end
function [y, s_next] = mod_filt_int(x, s, b, a, sh)
y_acc = (b(1)*x) + s(1);
y_raw = floor(y_acc / (2^sh));
if y_raw > 32767, y = 32767;
elseif y_raw < -32768, y = -32768;
else, y = y_raw;
end
s_next = [(b(2)*x) - (a(2)*y) + s(2), (b(3)*x) - (a(3)*y)];
end
function [spk, t_next] = mod_det_int(x, th, t)
SAT = -30000;
spk = 0;
t_next = t;
if t_next > 0, t_next = t_next - 1;
elseif (x < th) && (x > SAT), spk = 1;
    t_next = 20;
end
end
function [v_next] = mod_dec_int(bin, v, m1, m2, sh, max_v)
t1 = m1 * v;
t2 = (m2 * bin) * (2^sh);
v_raw = floor((t1 + t2) / (2^sh));
if v_raw > max_v, v_next = max_v;
elseif v_raw < -max_v, v_next = -max_v;
else, v_next = v_raw;
end
end