@RestResource(urlMapping='/pwrev/asset-management/*')
global with sharing class AssetManagementRESTHandler {
    public AssetManagementRESTHandler() {

    }
    // REST Handling
    private class IncomingPayload {
        Order order;
        Asset asset;
        SBQQ__Quote__c quote;
        Opportunity opportunity;
        ID accountId;
        Boolean salesOnly;
        Boolean saveQuoteLines;
        Boolean ignoreErrors;
        Date requestDate;
    }

    // REST handling
    @HttpPost
    global static void HandlePost() {
        IncomingPayload req = new IncomingPayload();
        if(RestContext.request.requestBody != null && RestContext.request.requestBody != Blob.valueOf('')) {
            req = (IncomingPayload) JSON.deserialize(RestContext.request.requestBody.toString(), IncomingPayload.class);
        }
        String[] path = RestContext.request.requestURI.split('/');
        // Should be ['', 'pwrev', 'asset-management', '...']
        System.debug(path);
        if (path[3] == 'asset') {
            Asset a = [SELECT Id, AccountId, Name, RootAssetId FROM Asset WHERE Id = :path[4]];
            switch on path[5] {
                when 'modify' {
                    RestContext.response.statusCode = 200;
                    RestContext.response.addHeader('Content-Type', 'application/json');
                    if(req.quote != null) {
                        List<SBQQ__QuoteLine__c> qls = AssetManagement.ModifyAsset(a, req.requestDate, req.quote, req.saveQuoteLines);                        
                        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(qls));
                    } else if(req.opportunity != null) {
                        SBQQ__Quote__c q = AssetManagement.ModifyAsset(a, req.requestDate, req.opportunity);
                        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(q));
                    } else {
                        SBQQ__Quote__c q = AssetManagement.ModifyAsset(a, req.requestDate);
                        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(q));
                    }
                }
                when else {
                    RestContext.response.statusCode = 400;
                    RestContext.response.responseBody = Blob.valueOf('{"error":"Unrecognised action on asset: ' + path[4] + '"}');
                }
            }
        } else if (path[3] == 'actions') {
            String action = path[4];
            if(action == 'cancel') {
                Asset a = [SELECT Quantity, CurrentQuantity, CurrentMrr, CurrentAmount, LifecycleStartDate, LifecycleEndDate, (SELECT Quantity FROM AssetStatePeriods), (SELECT ActionDate FROM AssetActions ORDER BY ActionDate DESC) FROM Asset WHERE Id = :req.asset.Id];
                Tranquility.CancelResult result = AssetManagement.CancelAsset(a);
                RestContext.response.responseBody = Blob.valueOf(JSON.serialize(result));
                RestContext.response.statusCode = 200;
                RestContext.response.addHeader('Content-Type', 'application/json');
            } else if(action == 'cancel-all') {
                List<Asset> assets = [SELECT Quantity, CurrentQuantity, CurrentMrr, CurrentAmount, LifecycleStartDate, LifecycleEndDate, (SELECT Quantity FROM AssetStatePeriods), (SELECT ActionDate FROM AssetActions ORDER BY ActionDate DESC) FROM Asset WHERE AccountId = :req.accountId AND Id NOT IN (SELECT AssetId FROM AssetAction WHERE Category = 'Cancellations') LIMIT 100];
                if(assets.size() == 0){
                    RestContext.response.responseBody = Blob.valueOf('Account has no active assets.');
                    RestContext.response.statusCode = 200;
                } else {
                    List<Asset> assetResults = new List<Asset>();
                    List<Tranquility.CancelResult> results = new List<Tranquility.CancelResult>();
                    for (Asset a : assets) {
                        try {
                            Tranquility.CancelResult result = AssetManagement.CancelAsset(a);
                            assetResults.add(result.asset);
                            results.add(result);
                        } catch(Exception e) {
                            if(e instanceof AssetManagement.NonCALMAssetException) {
                                //do nothing
                            } else if(req.ignoreErrors == null || !req.ignoreErrors) {
                                throw e;
                            }
                        }
                    }
                    System.debug('HandlePost -> update assetResults');
                    update assetResults; // <-- to set the status to Cancelled
                    RestContext.response.responseBody = Blob.valueOf(JSON.serialize(results));
                    RestContext.response.statusCode = 200;
                    RestContext.response.addHeader('Content-Type', 'application/json');
                }
            } else if(action == 'generate') {
                List<Asset> result;
                if(req.salesOnly != null) {
                    result = AssetManagement.GenerateAssetsFromOrder(req.order, req.salesOnly, null);
                } else {
                    result = AssetManagement.GenerateAssetsFromOrder(req.order, null);
                }
                RestContext.response.responseBody = Blob.valueOf(JSON.serialize(result));
                RestContext.response.statusCode = 200;
                RestContext.response.addHeader('Content-Type', 'application/json');
            } else {
                RestContext.response.responseBody = Blob.valueOf('Unrecognised action');
                RestContext.response.statusCode = 400;
            }
        }
    }
}