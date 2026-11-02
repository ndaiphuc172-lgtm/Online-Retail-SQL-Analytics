# KPI contract
USD; UTC; Website/App; một shipment mỗi đơn. Dữ liệu seed là mô phỏng.

| Chỉ tiêu | Công thức / grain / trạng thái |
|---|---|
| Recognized purchase | Đơn Delivered; OrderID duy nhất; đơn hoàn tiền toàn bộ vẫn tính purchase. |
| Merchandise sales | Tổng OrderItems.NetMerchandiseAmount của đơn Delivered; không thuế, không shipping. |
| Merchandise refund | Cộng cash Refunds trạng thái Completed theo OrderItemID qua ReturnItems; phân bổ theo NetMerchandiseAmount / LinePayableAmount; làm tròn hai chữ số một lần tại item rồi cộng lên. Mẫu số zero cần xử lý bằng NULLIF. |
| Net merchandise | Merchandise sales trừ merchandise refund. |
| Net revenue | Net merchandise cộng ShippingFee đúng một lần mỗi đơn Delivered; không thuế. |
| AOV | Net revenue / số đơn Delivered; mẫu số zero dùng NULLIF, không chia nguyên. |
| COGS / estimated profit | Quantity × UnitCostAtOrder từ item lịch sử; chưa có dữ liệu disposition sau return nên không suy ra COGS hoàn nhập. Profit là ước tính. |
| Customer revenue | Tổng net revenue theo CustomerID; observed revenue, không predicted CLV. |
| Cohort | Tháng đơn Delivered đầu tiên; sắp xếp OrderDate rồi OrderID; acquisition channel theo đơn đó. |
| Retention | CustomerID duy nhất có Delivered trong tháng offset / số khách cohort; không đếm nhiều đơn thành nhiều khách. |

Ngày doanh thu và refund trong báo cáo retrospective quy về OrderDate của đơn gốc. Refund cash có thể gồm tax; không dùng cash tổng thay merchandise refund. Giá và cost lịch sử lấy từ OrderItems, không lấy Products.Price hiện tại.

Cutoff UTC không bao gồm: seed nhỏ 2026-09-01T00:00:00; seed lớn 2026-10-01T00:00:00. Coverage phải được xác nhận từ dataset; không suy ra từ đơn cuối. Kỳ quan sát được không có hoạt động là zero; kỳ chưa quan sát là NULL; so sánh retention theo maturity. Snapshot trạng thái hiện tại không tái dựng lịch sử trạng thái.

Payment attempt grain khác order grain; Failed, Successful và retry là sự kiện riêng. Recovery chỉ dùng success có CreatedAt sau failed, đây là proxy chronology. Requested/Received return, inspection và refund settlement là các sự kiện riêng; Failed refund không tiêu hao approval.

SLA demo 48/72/120 giờ; phân loại từ elapsed seconds chưa làm tròn. Durations giữ phần giờ lẻ. Open aging loại terminal statuses và dùng timestamp quan sát thống nhất.

Tỷ lệ return theo order và theo unit phải dùng denominator đúng grain. Refund rate cần cùng tax basis giữa numerator và denominator. Các tỷ lệ chuyên biệt phải đọc alias/công thức trong SQL; kết quả kiểm thử cuối nằm trong evidence/. Zero/NULL không được tự thay thế nếu thay đổi ý nghĩa của metric.

Hạn chế: dữ liệu mô phỏng, snapshot hồi cứu và số mẫu hữu hạn; không suy ra CLV dự đoán hoặc tính đúng cho mọi dữ liệu tương lai.

## Owner-selected legacy view meaning
User explicitly chose all-order statuses and historical Quantity × UnitPrice, before discount/refund, excluding shipping. vw_CustomerOrders fix uses COUNT(DISTINCT OrderID) and historical UnitPrice; no Delivered filter or net revenue is introduced. These gross metrics intentionally differ from A–G recognized/net metrics and must be labelled accordingly. Orders without item rows and customers without orders remain excluded by the existing inner-join semantics.

legacy_views/test_recent_orders_patch.sql temporarily creates/alters both views inside a transaction on the previously authorized small disposable database only. It checks eight all-status orders, customer order counts and invariance to catalog-price change. All changes roll back on success or error. Syntax zero errors; runtime PASS theo legacy_view_test_pasted.json. No live view deployment performed. Expected marker LEGACY_VIEW_PATCH_TEST_COMPLETE_ROLLED_BACK.
