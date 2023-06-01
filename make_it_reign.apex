// DO IT DO IT DO IT DO IT DO IT
// JanusButton.click();
/*
List<Asset> existing = [
    SELECT Id
    FROM Asset
    WHERE Account.Name LIKE 'Migration Test %'
];
Id moveToAccId = [SELECT Id FROM Account WHERE Name = '[DELETED ASSETS]'].Id;
for (Asset a : existing) {
    a.AccountId = moveToAccId;
}
List<Asset_Migration_Record__c> existingRecs = [SELECT Id FROM Asset_Migration_Record__c];
for (Asset_Migration_Record__c rec : existingRecs) {
    rec.Asset__c = null;
    rec.Has_Error__c = false;
    rec.Error__c = null;
    // rec.Asset_Number__c = null;
    // rec.Contract_Asset_Number__c = null;
    rec.Revision__c = null;
    // rec.Contract_Revision__c = null;
}
update existing;
update existingRecs;
*/
/*
Janus.reign(
    new Janus.BatchConfig(
        5, // Blocks per batch
        null, // Total blocks per customer (limit)
        null, // Total customers (limit)
        5, // concurrent batches,
        null // Serenity.BatchConfig
    ),
    customerIds
);
*/

Database.executeBatch(new ReignBatchable(
    new Janus.BatchConfig(
        5, // Blocks per batch
        null, // Total blocks per customer (limit)
        null, // Total customers (limit)
        5, // concurrent batches,
        null // Serenity.BatchConfig
    )),
    1
);
// 0018E00001zm5FwQAI
// 0018E0000209UNYQA2