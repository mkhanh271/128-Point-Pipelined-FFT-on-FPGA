%% =====================================================
%% FFT 128-POINT RADIX-2 DECIMATION-IN-FREQUENCY (DIF)
%% PHIÊN BẢN: TỰ ĐỘNG TẠO DỮ LIỆU + SO SÁNH HARDWARE
%% =====================================================
clear all; close all; clc;

%% Cấu hình chung
N = 128;                    
NUM_STAGES = log2(N);       
FIXED_POINT_BITS = 8;       

fprintf('========================================\n');
fprintf('  FFT 128-POINT DIF + HARDWARE COMPARE\n');
fprintf('========================================\n\n');

%% =====================================================
%% 1. ĐỌC DỮ LIỆU ĐẦU VÀO (XỬ LÝ LỖI FILE)
%% =====================================================
fprintf('[1/7] Đọc dữ liệu đầu vào...\n');
filename_input = 'fft_input_complex.txt';

if isfile(filename_input)
    fprintf('   ✓ Tìm thấy file "%s"\n', filename_input);
    fid = fopen(filename_input, 'r');
    input_data = fscanf(fid, '%d %d', [2, N])';
    fclose(fid);
    x_real = input_data(:, 1);
    x_imag = input_data(:, 2);
    x = x_real + 1i * x_imag;
else
    fprintf('   ⚠ Không tìm thấy file "%s"!\n', filename_input);
    fprintf('   → Tạo dữ liệu mẫu (Sóng sin + Nhiễu)...\n');
    
    % Tạo dữ liệu mẫu: Sóng 10Hz trộn với sóng 30Hz
    Fs = 128; 
    t = 0:N-1;
    sig = 30*sin(2*pi*10*t/Fs) + 20*cos(2*pi*30*t/Fs); 
    
    x_real = round(sig)'; 
    x_imag = zeros(N, 1);
    
    % Clamp 8-bit
    x_real = max(-128, min(127, x_real));
    x = x_real + 1i * x_imag;
end

fprintf('   ✓ Đã load %d điểm\n', length(x));
fprintf('   Range: Real [%d, %d], Imag [%d, %d]\n\n', ...
        min(x_real), max(x_real), min(x_imag), max(x_imag));

%% =====================================================
%% 2. TÍNH TWIDDLE FACTORS
%% =====================================================
fprintf('[2/7] Tính toán twiddle factors...\n');
W = exp(-1i * 2 * pi * (0:N/2-1) / N);
fprintf('   ✓ Tạo %d twiddle factors\n\n', length(W));

%% =====================================================
%% 3. THUẬT TOÁN FFT RADIX-2 DIF (CORE)
%% =====================================================
fprintf('[3/7] Tính toán FFT (DIF Algorithm)...\n');
X = x; % Bắt đầu với input tự nhiên

for stage = 1:NUM_STAGES
    % DIF: Khối to -> Khối nhỏ
    span = N / (2^stage); 
    num_blocks = 2^(stage-1);
    
    fprintf('   Stage %d/%d: span=%d, blocks=%d\n', stage, NUM_STAGES, span, num_blocks);
    
    for block = 0:num_blocks-1
        offset = block * 2 * span;
        for k = 0:span-1
            top = offset + k + 1;      
            bot = top + span;
            
            % --- CÁNH BƯỚM DIF ---
            % 1. Cộng/Trừ trước
            upper = X(top) + X(bot);
            lower = X(top) - X(bot);
            
            % 2. Nhánh dưới nhân W sau
            w_idx = k * (2^(stage-1)); 
            
            X(top) = upper;         
            X(bot) = lower * W(w_idx + 1); 
        end
    end
end
fprintf('   ✓ Hoàn thành FFT\n\n');

%% =====================================================
%% 4. BIT-REVERSAL ORDERING (ĐẦU RA)
%% =====================================================
fprintf('[4/7] Sắp xếp lại đầu ra (Bit-Reversal)...\n');
X_natural_order = zeros(N, 1);
for k = 0:N-1
    reversed_idx = bin2dec(fliplr(dec2bin(k, NUM_STAGES)));
    X_natural_order(reversed_idx + 1) = X(k + 1);
end
X = X_natural_order; 
fprintf('   ✓ Đã sắp xếp bit-reversal\n\n');

%% =====================================================
%% 5. MÔ PHỎNG FIXED-POINT ĐẦU RA
%% =====================================================
fprintf('[5/7] Chuyển đổi Fixed-Point 8-bit...\n');
X_scaled = X / N; % Scaling by 1/N
X_real_fp = round(real(X_scaled));
X_imag_fp = round(imag(X_scaled));

% Clamp 8-bit [-128, 127]
X_real_fp = max(-128, min(127, X_real_fp));
X_imag_fp = max(-128, min(127, X_imag_fp));

X_fixed_point = X_real_fp + 1i * X_imag_fp;
fprintf('   ✓ Output range: Real [%d, %d], Imag [%d, %d]\n\n', ...
        min(X_real_fp), max(X_real_fp), min(X_imag_fp), max(X_imag_fp));

%% =====================================================
%% 6. SO SÁNH VỚI HARDWARE OUTPUT
%% =====================================================
fprintf('[6/7] So sánh với Hardware Output...\n');
filename_hw = 'fft_output_complex.txt';

has_hw_data = false;

if isfile(filename_hw)
    fprintf('   ✓ Tìm thấy file "%s"\n', filename_hw);
    
    fid = fopen(filename_hw, 'r');
    hw_data = fscanf(fid, '%d %d', [2, N])';
    fclose(fid);
    
    hw_real = hw_data(:, 1);
    hw_imag = hw_data(:, 2);
    hw_complex = hw_real + 1i * hw_imag;
    
    has_hw_data = true;
    
    % Tính toán lỗi
    diff_real = X_real_fp - hw_real;
    diff_imag = X_imag_fp - hw_imag;
    
    max_error_real = max(abs(diff_real));
    max_error_imag = max(abs(diff_imag));
    mean_error_real = mean(abs(diff_real));
    mean_error_imag = mean(abs(diff_imag));
    
    num_perfect = sum((diff_real == 0) & (diff_imag == 0));
    error_indices = find((diff_real ~= 0) | (diff_imag ~= 0));
    
    % In kết quả so sánh
    fprintf('\n');
    fprintf('========================================\n');
    fprintf('  KẾT QUẢ SO SÁNH\n');
    fprintf('========================================\n');
    fprintf('Max error (Real)     : %d\n', max_error_real);
    fprintf('Max error (Imag)     : %d\n', max_error_imag);
    fprintf('Mean error (Real)    : %.3f\n', mean_error_real);
    fprintf('Mean error (Imag)    : %.3f\n', mean_error_imag);
    fprintf('Perfect matches      : %d/%d (%.1f%%)\n', num_perfect, N, 100*num_perfect/N);
    fprintf('Points with errors   : %d\n', length(error_indices));
    fprintf('========================================\n\n');
    
    % Đánh giá kết quả
    if max_error_real == 0 && max_error_imag == 0
        fprintf('✓✓✓ HOÀN HẢO! 100%% khớp với hardware!\n\n');
    elseif max_error_real <= 1 && max_error_imag <= 1
        fprintf('✓ XUẤT SẮC! Lỗi trong phạm vi ±1\n');
        fprintf('  Lỗi nhỏ này do:\n');
        fprintf('  - Sai khác quantization fixed-point\n');
        fprintf('  - Hardware dùng convergent rounding\n');
        fprintf('  - Twiddle factor quantization (12-14 bits)\n\n');
    else
        fprintf(' Có lỗi lớn hơn mong đợi\n\n');
    end
    
    % Chi tiết các điểm lỗi
    if ~isempty(error_indices) && length(error_indices) <= 25
        fprintf('Chi tiết các điểm lỗi:\n');
        fprintf('%-6s %-10s %-10s %-10s %-10s %-8s\n', ...
                'k', 'MAT Re', 'HW Re', 'MAT Im', 'HW Im', 'Error');
        fprintf('--------------------------------------------------------------\n');
        for i = 1:length(error_indices)
            k = error_indices(i) - 1;
            err = abs(diff_real(k+1)) + abs(diff_imag(k+1));
            fprintf('%-6d %-10d %-10d %-10d %-10d %-8d\n', k, ...
                    X_real_fp(k+1), hw_real(k+1), ...
                    X_imag_fp(k+1), hw_imag(k+1), err);
        end
        fprintf('\n');
    end
    
    % Lưu kết quả MATLAB
    fid = fopen('matlab_fft_output.txt', 'w');
    for k = 1:N
        fprintf(fid, '%4d %4d\n', X_real_fp(k), X_imag_fp(k));
    end
    fclose(fid);
    fprintf('   ✓ Đã lưu: matlab_fft_output.txt\n\n');
    
else
    fprintf('   Không tìm thấy file "%s"\n', filename_hw);
    fprintf('   → Bỏ qua so sánh hardware\n\n');
end

%% =====================================================
%% 7. VẼ ĐỒ THỊ (VISUALIZATION)
%% =====================================================
fprintf('[7/7] Tạo đồ thị...\n');

% ========== FIGURE 1: Input Signal ==========
figure('Position', [50, 50, 1400, 700], 'Color', 'w');

subplot(3,1,1);
stem(0:N-1, real(x), 'b', 'LineWidth', 1.2, 'MarkerSize', 4);
title('Input Signal - Real Part', 'FontSize', 13, 'FontWeight', 'bold', 'Color', 'k');
xlabel('Sample index n','Color', 'k'); ylabel('Re{x[n]}', 'Color', 'k');
set(gca,'XColor','k','YColor','k');
xlim([-2 N+1]); ylim([min(real(x))-10 max(real(x))+10]); grid on;

subplot(3,1,2);
stem(0:N-1, imag(x), 'Color', [0 0.7 0], 'LineWidth', 1.2, 'MarkerSize', 4);
title('Input Signal - Imaginary Part', 'FontSize', 13, 'FontWeight', 'bold', 'Color', 'k');
xlabel('Sample index n','Color', 'k'); ylabel('Im{x[n]}', 'Color', 'k');
set(gca,'XColor','k','YColor','k');
xlim([-2 N+1]); ylim([min(imag(x))-10 max(imag(x))+10]); grid on;

subplot(3,1,3);
stem(0:N-1, abs(x), 'r', 'LineWidth', 1.2, 'MarkerSize', 4);
title('Input Signal - Magnitude', 'FontSize', 13, 'FontWeight', 'bold', 'Color', 'k');
xlabel('Sample index n', 'Color', 'k'); ylabel('|x[n]|', 'Color', 'k');
set(gca,'XColor','k','YColor','k');
xlim([-2 N+1]); ylim([0 max(abs(x))+20]); grid on;

sgtitle('128-Point FFT Input (Time Domain)', 'FontSize', 15, 'FontWeight', 'bold', 'Color', 'k');

% ========== FIGURE 2: FFT Output Spectrum ==========
figure('Position', [100, 100, 1400, 700], 'Color', 'w');

output_mag = abs(X_fixed_point);

% Tìm đỉnh
threshold = 12;
peaks_idx = find(output_mag >= threshold);

subplot(2,1,1);
stem(0:N-1, output_mag, 'b', 'LineWidth', 1.2, 'MarkerSize', 4); hold on;
stem(peaks_idx-1, output_mag(peaks_idx), 'r', 'LineWidth', 1.5, ...
     'MarkerSize', 5, 'MarkerFaceColor', 'r');

% Gán nhãn cho các đỉnh
[~, sort_idx] = sort(output_mag, 'descend');
top_n = min(10, length(peaks_idx));
for i = 1:top_n
    k = sort_idx(i) - 1;
    if output_mag(k+1) >= threshold
        text(k, output_mag(k+1)+0.8, sprintf('k=%d', k), ...
             'FontSize', 9, 'HorizontalAlignment', 'center', ...
             'FontWeight', 'bold', 'Color', [0.6 0 0]);
    end
end

title('FFT Output - Magnitude Spectrum (DIF)', 'FontSize', 13, 'FontWeight', 'bold', 'Color', 'k');
xlabel('Frequency index k', 'Color', 'k'); ylabel('|X[k]|', 'Color', 'k');
set(gca,'XColor','k','YColor','k');
xlim([-2 N+1]); ylim([0 max(output_mag)*1.2]); grid on;
legend('All frequency bins', 'Dominant frequencies (≥12)', 'Location', 'northeast');

subplot(2,1,2);
output_phase = angle(X_fixed_point);
stem(0:N-1, output_phase, 'Color', [0.8 0.4 0], 'LineWidth', 1.2, 'MarkerSize', 4);
title('FFT Output - Phase Spectrum', 'FontSize', 13, 'FontWeight', 'bold', 'Color', 'k');
xlabel('Frequency index k', 'Color', 'k'); ylabel('Phase (radians)', 'Color', 'k');
set(gca,'XColor','k','YColor','k');
xlim([-2 N+1]); ylim([-pi-0.5 pi+0.5]); grid on;
yticks([-pi -pi/2 0 pi/2 pi]);
yticklabels({'-π', '-π/2', '0', 'π/2', 'π'});

sgtitle('128-Point FFT Output (Frequency Domain - DIF)', 'FontSize', 15, 'FontWeight', 'bold',  'Color', 'k');

% ========== FIGURE 3: Hardware Comparison (nếu có) ==========
if has_hw_data
    figure('Position', [150, 150, 1400, 900], 'Color', 'w');
    
    hw_mag = abs(hw_complex);
    
    % Real part comparison
    subplot(3,2,1);
    plot(0:N-1, hw_real, 'r-', 'LineWidth', 2); hold on;
    plot(0:N-1, X_real_fp, 'b--', 'LineWidth', 1.5);
    title('Real Part Comparison', 'FontSize', 12, 'FontWeight', 'bold',  'Color', 'k');
    xlabel('Frequency index k',  'Color', 'k'); ylabel('Re{X[k]}',  'Color', 'k');
    set(gca,'XColor','k','YColor','k');
    legend('Hardware', 'MATLAB DIF', 'Location', 'best');
    grid on; xlim([-2 N+1]);
    
    % Imaginary part comparison
    subplot(3,2,2);
    plot(0:N-1, hw_imag, 'r-', 'LineWidth', 2); hold on;
    plot(0:N-1, X_imag_fp, 'b--', 'LineWidth', 1.5);
    title('Imaginary Part Comparison', 'FontSize', 12, 'FontWeight', 'bold', 'Color', 'k');
    xlabel('Frequency index k', 'Color', 'k'); ylabel('Im{X[k]}', 'Color', 'k');
    set(gca,'XColor','k','YColor','k');
    legend('Hardware', 'MATLAB DIF', 'Location', 'best');
    grid on; xlim([-2 N+1]);
    
    % Real error
    subplot(3,2,3);
    stem(0:N-1, abs(diff_real), 'r', 'LineWidth', 1.2, 'MarkerSize', 4);
    title(sprintf('Real Part Error (Max=%d)', max_error_real), ...
          'FontSize', 12, 'FontWeight', 'bold', 'Color', 'k');
    xlabel('Frequency index k','Color', 'k'); ylabel('|Error|','Color', 'k');
    set(gca,'XColor','k','YColor','k');
    grid on; xlim([-2 N+1]);
    ylim([-0.5 max(max_error_real,1)+0.5]);
    
    % Imaginary error
    subplot(3,2,4);
    stem(0:N-1, abs(diff_imag), 'b', 'LineWidth', 1.2, 'MarkerSize', 4);
    title(sprintf('Imaginary Part Error (Max=%d)', max_error_imag), ...
          'FontSize', 12, 'FontWeight', 'bold','Color', 'k');
    xlabel('Frequency index k','Color', 'k'); ylabel('|Error|','Color', 'k');
    set(gca,'XColor','k','YColor','k');
    grid on; xlim([-2 N+1]);
    ylim([-0.5 max(max_error_imag,1)+0.5]);
    
    % Magnitude comparison
    subplot(3,2,5);
    plot(0:N-1, hw_mag, 'r-', 'LineWidth', 2); hold on;
    matlab_mag = abs(X_fixed_point);
    plot(0:N-1, matlab_mag, 'b--', 'LineWidth', 1.5);
    title('Magnitude Comparison', 'FontSize', 12, 'FontWeight', 'bold','Color', 'k');
    xlabel('Frequency index k','Color', 'k'); ylabel('|X[k]|','Color', 'k');
    set(gca,'XColor','k','YColor','k');
    legend('Hardware', 'MATLAB DIF', 'Location', 'best');
    grid on; xlim([-2 N+1]);
    
    % Error distribution histogram
    subplot(3,2,6);
    total_err = abs(diff_real) + abs(diff_imag);
    histogram(total_err, 'BinWidth', 1, 'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'k');
    title(sprintf('Error Distribution (%d points with errors)', length(error_indices)), ...
          'FontSize', 12, 'FontWeight', 'bold','Color', 'k');
    xlabel('Total error (|Re error| + |Im error|)','Color', 'k');
    ylabel('Number of frequency bins','Color', 'k');
    set(gca,'XColor','k','YColor','k');
    grid on;
    
    sgtitle(sprintf('Hardware vs MATLAB DIF: %.1f%% Match (%d/%d points)', ...
            100*num_perfect/N, num_perfect, N), ...
            'FontSize', 15, 'FontWeight', 'bold','Color', 'k');
end

fprintf('   ✓ Đã tạo %d đồ thị\n\n', 2 + has_hw_data);

%% =====================================================
%% 8. IN KẾT QUẢ DOMINANT FREQUENCIES
%% =====================================================
fprintf('========================================\n');
fprintf('  DOMINANT FREQUENCIES\n');
fprintf('========================================\n');
for i = 1:min(length(peaks_idx), 15)
    k = peaks_idx(i) - 1;
    fprintf('Bin k=%3d: Mag=%5.2f (Re=%4d, Im=%4d)\n', ...
        k, output_mag(peaks_idx(i)), X_real_fp(k+1), X_imag_fp(k+1));
end
fprintf('========================================\n\n');

fprintf('✓ ĐÃ CHẠY XONG!\n');