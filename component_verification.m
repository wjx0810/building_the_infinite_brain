clc;
clear;
close all;

% Filter verification
fs = 30000;
frac = 12;
scale = 2^frac;
fc = 250;
wc = tan(pi * fc / fs);
norm = 1 + sqrt(2)*wc + wc^2;
b = [1, -2, 1] / norm;
a = [1, (2*(wc^2 - 1))/norm, (1 - sqrt(2)*wc + wc^2)/norm];

% Frequency response
N_fft = 1000;
f_axis = linspace(0, fs/2, N_fft);
omega = 2 * pi * f_axis / fs;
z = exp(1j * omega);
num_poly = b;
den_poly = a;
H_num = polyval(num_poly, exp(-1j*omega));
H_den = polyval(den_poly, exp(-1j*omega));
H = H_num ./ H_den;
mag_db = 20*log10(abs(H));
phase_deg = angle(H) * (180/pi);

% Plot filter freq response
subplot(2,2,1);
semilogx(f_axis, mag_db);
grid on;
title('High-Pass Filter Frequency Response');
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
xline(250, '--', 'f_c = 250Hz');

subplot(2,2,3);
semilogx(f_axis, phase_deg);
grid on;
title('High-Pass Filter Phase Response');
xlabel('Frequency (Hz)');
ylabel('Phase (deg)');

% Kalman filter verification
M1 = 0.95; % Decay
M2 = 0.20; % Input gain
M1_int = round(M1 * scale);
M2_int = round(M2 * scale);
max_v_int = 5.0 * scale;

% Generate step input
input_bins = [zeros(1,10), ones(1,30), zeros(1,40)];
steps = length(input_bins);

% Store result
out_float = zeros(1, steps);
out_fix = zeros(1, steps);

% State Init
vel_float = 0;
vel_fix = 0;

% Simulation Loop
for k = 1:steps
    bin_in = input_bins(k);

    % Floating point
    vel_float = vel_float * M1 + bin_in * M2;
    out_float(k) = vel_float;

    % Fixed point
    t1 = M1_int * vel_fix;
    t2 = (M2_int * bin_in) * (2^frac); % Shift bin up to match precision
    % Fixed point equation from mod_dec_int
    v_raw = floor((t1 + t2) / scale);

    % Saturation
    if v_raw > max_v_int, vel_fix = max_v_int;
    elseif v_raw < -max_v_int, vel_fix = -max_v_int;
    else, vel_fix = v_raw;
    end

    out_fix(k) = double(vel_fix) / scale;
end

% Plot step response
subplot(1,2,2);
plot(out_float);
hold on;
plot(out_fix, '--');
title('Kalman Filter Step Response');
xlabel('Time Steps (Bins)');
ylabel('Velocity State');
legend('Float Ideal', 'Fixed Point');
grid on;

% Error analysis
max_error = max(abs(out_float - out_fix));
text(40, 0.5, sprintf('Max Err: %.5f', max_error));