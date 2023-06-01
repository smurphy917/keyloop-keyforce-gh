public with sharing class JanusButton {
    public static void click(){
        // LARGE Customer
        List<Id> customerIds = new List<Id>{'0018E00001zmLHSQA2'};
        // MEDIUM Customer
        // List<Id> customerIds = new List<Id>{'0018E0000208yz4QAA'};

        Serenity.BatchConfig assetConfig = new Serenity.BatchConfig();
        assetConfig.namedCredentials = new List<String>{'Salesforce'};

        Janus.reign(
            new Janus.BatchConfig(
                5, // Blocks per batch
                null, // Total blocks per customer (limit)
                null, // Total customers (limit)
                5, // concurrent batches,
                assetConfig // Serenity.BatchConfig
            ),
            customerIds
        );
    }
}



/*

LARGE (0018E00001zmLHSQA2)
1204 site line assets created in load
3143 migration records
    1683 matched to asset
    1460 not matched to asset

MEDIUM (0018E0000208yz4QAA)
1122 site line assets created in load
3163 migration records
    2784 matched to asset
    379 not matched to asset

*/