SELECT
    line.[Sales Contract No_] Source_Reference__c,
    line.[Item No_] [Product__r.ExternalId__c],
    line.[Starting Date] Start_Date__c,
    line.[Original Starting Date] [Original_Start_Date__c],
    line.[Expiration Date] [End_Date__c],
    line.[Quantity] [Quantity__c],
    line.[MUP] [Price__c],
    line.[Serial Number] [Serial_Number__c],
    header.[Customer No_] [Customer__r.ExternalId__c],
    header.[Site No_] [Site__r.ExternalId__c]
  FROM [DataMigration].[staging].[SalesPOC_RecurringContractLine] line
  LEFT OUTER JOIN [DataMigration].[staging].[SalesPOC_RecurringContractHeader] header ON line.[Document No_] = header.[No_]
  WHERE [Item No_] != 'GENERIC 01' AND
    [Expiration Date] > '1753-01-01'
  ORDER BY [Document No_]
  OFFSET 0 ROWS
  FETCH FIRST 1000 ROWS ONLY;