# Hiệu năng: bằng chứng mới

Đã nhận runtime_performance.txt; có ALL_PERFORMANCE_COMPLETE và không thấy Msg lỗi.

| Module | CPU cộng (ms) | Elapsed cộng (ms) | Số timing records |
|---|---:|---:|---:|
| A/B/C | 20345 | 21221 | 22 |
| D | 375 | 772 | 9 |
| E | 265 | 328 | 16 |
| F | 625 | 781 | 15 |
| G | 328 | 371 | 19 |

Số trên là tổng message thời gian thực thi statement, không phải wall-clock và không gồm compile time. Logical reads được tổng hợp theo bảng trong performance_validation.json; không cộng cache rows lặp theo QueryHash.

Phần cached plans không có dòng dữ liệu trong report, nên chưa có bằng chứng kế hoạch thực thi từ phần này. Không suy luận nguyên nhân vì cache có thể thay đổi và bộ lọc có thể không khớp. Chưa có actual plan hoặc phép đo trước/sau rewrite/index.

Đề xuất cần thử nghiệm: giảm quét lặp facts/OrderItems/Refunds/Payments và thử index join/filter phù hợp. Đo cả chi phí tạo index và nhiều lần chạy đại diện trước khi kết luận. Worktable reads không tự chứng minh spill. Chưa áp dụng index hoặc thay đổi setting.
