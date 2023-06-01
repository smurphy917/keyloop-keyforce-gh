%dw 2.0
input records application/csv
output application/apex
---
records map(record) -> {
 Account: record.CUSTOMER_ACCOUNT,
 Site: record.SITE_ACCOUNT,
 Product: record.PRODUCT_CODE,
 Quantity: record.QUANTITY,
 OriginalStartDate: record.ORIGINAL_START_DATE,
 StartDate: record.START_DATE,
 EndDate: record.END_DATE,
 Price: record.PRICE
} as Object {class: "Janus.DataRow"}