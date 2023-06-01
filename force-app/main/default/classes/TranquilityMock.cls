global with sharing class TranquilityMock implements HttpCalloutMock {

    public List<Id> insertedIds = new List<Id>();
    public List<Id> updatedIds = new List<Id>();
    public List<Id> canceledIds = new List<Id>();
    public Map<String,String> errorResponse;
    public Integer statusCode;

    public TranquilityMock(){}

    public TranquilityMock (Boolean requestLimitError) {
        this.errorResponse = new Map<String,String>();
        this.errorResponse.put('errorCode', 'REQUEST_LIMIT_EXCEEDED');
        this.statusCode = 503;
    }

    private class AssetServiceMockResponse {
        public SObject asset;
        public SObject assetAction;
        public List<SObject> assetActionSources;
        public List<SObject> assetStatePeriods;
    }

    private void validateASPs(List<Tranquility.AssetStatePeriodInput> asps) {
        for (Tranquility.AssetStatePeriodInput asp : asps) {
            System.assertNotEquals(null, asp.startDate, 'Start date is required on Asset State Period');
            System.assertNotEquals(null, asp.amount, 'Amount is required on Asset State Period');
            System.assert(asp.endDate == null ? true : asp.startDate < asp.endDate, 'End Date [' + asp.endDate + '] must be after Start Date [' + asp.startDate + ']');
        }
    }

    private void validateASPChange(Id assetId, List<Tranquility.AssetStatePeriodInput> asps) {
        Boolean matchedAsp = false;
        List<StagedAssetStatePeriod> currentASPs = StagedAssetStatePeriod.fromList([SELECT Id, StartDate, EndDate, AssetId, Amount, Mrr FROM AssetStatePeriod WHERE AssetId = :assetId]);
        if(currentASPs.size() == 0 && Test.isRunningTest()) {
            currentASPs = new List<StagedAssetStatePeriod>();
            for (StagedRecord rec : StagedDatabase.query(new FindASPsByAssetId(assetId))) {
                currentASPs.add((StagedAssetStatePeriod) rec);
            }
        }
        if(currentASPs.size() == 0) {
            currentASPs = ((StagedAsset) StagedDatabase.get(assetId)).AssetStatePeriods;
        }
        asps.sort();
        Tranquility.AssetStatePeriodInput aspi = asps[0];
        for (StagedAssetStatePeriod asp : currentASPs) {
            if(aspi.startDate == asp.StartDate) {
                matchedAsp = true;
                break;
            }
        }
        if(!matchedAsp) {
            System.debug('CURRENT ASPS: ' + JSON.serialize(currentASPs));
            System.debug('REQUEST ASPS: ' + JSON.serialize(asps));
        }
        System.assert(matchedAsp, 'Cannot find matching asset state period for start date: ' + aspi.startDate + ' for assetId: ' + assetId);
    }
    
    global HTTPResponse respond(HTTPRequest req) {
        if(this.errorResponse != null) {
            HttpResponse resp = new HttpResponse();
            resp.setStatus(String.valueOf(this.statusCode));
            resp.setBody(JSON.serialize(new List<Map<String,String>>{this.errorResponse}));
            resp.setHeader('Content-Type', 'application/json');
            this.errorResponse = null;
            this.statusCode = null;
            return resp;
        }
        Tranquility.AssetServiceResponse resp = new Tranquility.AssetServiceResponse();
        Tranquility.AssetRequest assetReq;
        String[] pathComps = req.getEndpoint().split('/');
        String action = pathComps[pathComps.size() - 1];
        if(req.getMethod() == 'POST') {
            switch on action {
                when 'generate' {
                    assetReq = (Tranquility.GenerateAssetRequest) TranquilityParser.parseRequest(req.getBody(), Tranquility.GenerateAssetRequest.class);
                    System.assertNotEquals(null, ((Tranquility.GenerateAssetRequest) assetReq).productId, 'ProductId is required');
                    System.assertNotEquals(null, ((Tranquility.GenerateAssetRequest) assetReq).accountId, 'AccountId is required');
                    System.assertNotEquals(0, ((Tranquility.GenerateAssetRequest) assetReq).assetStatePeriods.size(), 'Asset state periods are required');
                    System.assertNotEquals(null, ((Tranquility.GenerateAssetRequest) assetReq).assetAction, 'Asset action is required');
                    validateASPs(((Tranquility.GenerateAssetRequest) assetReq).assetStatePeriods);
                    for (Tranquility.AssetStatePeriodInput asp : ((Tranquility.GenerateAssetRequest) assetReq).assetStatePeriods) {
                        if (asp.amount == null) {
                            System.assert(false, 'AssetStatePeriod.Amount is required.');
                        }
                        if (asp.startDate == null) {
                            System.assert(false, 'AssetStatePeriod.StartDate is required.');
                        }
                    }
                    resp.asset = new Asset(Id=TestUtility.getFakeId(Schema.Asset.getSObjectType()));
                    this.insertedIds.add(resp.asset.Id);
                }
                when 'change' {
                    assetReq = (Tranquility.ChangeAssetRequest) TranquilityParser.parseRequest(req.getBody(), Tranquility.ChangeAssetRequest.class);
                    System.assertNotEquals(0, ((Tranquility.ChangeAssetRequest) assetReq).assetStatePeriods.size(), 'Asset state periods are required');
                    System.assertNotEquals(null, ((Tranquility.ChangeAssetRequest) assetReq).assetAction, 'Asset action is required');
                    validateASPs(((Tranquility.ChangeAssetRequest) assetReq).assetStatePeriods);
                    validateASPChange(((Tranquility.ChangeAssetRequest) assetReq).assetId, ((Tranquility.ChangeAssetRequest) assetReq).assetStatePeriods);
                    if(((Tranquility.ChangeAssetRequest) assetReq).assetId == null) {
                        HTTPResponse httpResp = new HTTPResponse();
                        httpResp.setStatusCode(400);
                        httpResp.setHeader('Content-Type', 'application/json');
                        Map<String,String> respBody = new Map<String,String>();
                        respBody.put('error', 'assetId is required');
                        httpResp.setBody(JSON.serialize(respBody));
                        return httpResp;
                    } else if(!PWUtils.isId(((Tranquility.ChangeAssetRequest) assetReq).assetId)) {
                        HTTPResponse httpResp = new HTTPResponse();
                        httpResp.setStatusCode(400);
                        httpResp.setHeader('Content-Type', 'application/json');
                        Map<String,String> respBody = new Map<String,String>();
                        respBody.put('error', 'invalid values provided for assetId');
                        httpResp.setBody(JSON.serialize(respBody));
                        return httpResp;
                    }
                    resp.asset = new Asset(Id=((Tranquility.ChangeAssetRequest) assetReq).assetId);
                    this.updatedIds.add(resp.asset.Id);
                }
                when 'cancel' {
                    assetReq = (Tranquility.CancelAssetRequest) TranquilityParser.parseRequest(req.getBody(), Tranquility.CancelAssetRequest.class);
                    Id assetId = pathComps[pathComps.size() - 3];
                    System.assertNotEquals(null, ((Tranquility.CancelAssetRequest) assetReq).assetStatePeriod, 'Asset state period is required');
                    System.assertNotEquals(null, ((Tranquility.CancelAssetRequest) assetReq).assetAction, 'Asset action is required');
                    resp.asset = new Asset(Id=pathComps[pathComps.size() - 3]);
                    List<Tranquility.AssetStatePeriodInput> asps = new List<Tranquility.AssetStatePeriodInput>{((Tranquility.CancelAssetRequest) assetReq).assetStatePeriod};
                    validateASPs(asps);
                    validateASPChange(assetId, asps);
                    this.canceledIds.add(resp.asset.Id);
                }
            }
        }
        resp.assetAction = new AssetAction(
            Id=TestUtility.getFakeId(Schema.AssetAction.getSObjectType()),
            Type=action,
            CategoryEnum=assetReq.assetAction.category,
            ActionDate=assetReq.assetAction.actionDate,
            QuantityChange=assetReq.assetAction.quantityChange,
            MrrChange=assetReq.assetAction.mrrChange,
            Amount=assetReq.assetAction.amount
        );

        System.assertNotEquals(null, assetAction.ActionDate);
        System.assertNotEquals(null, assetAction.QuantityChange);
        System.assertNotEquals(null, assetAction.CategoryEnum);
        System.assertNotEquals(null, assetAction.MrrChange);
        System.assertNotEquals(null, assetAction.Amount);
        // Need to use the untyped request here as JSON.deserialize drops elements that don't conform to the type when a referenced vs. nonreferenced asset action source input is provided
        // TODO: create a real parser to return the right type for assetActionSources
        for(Tranquility.AssetActionSourceInput input : assetReq.assetActionSources) {
            AssetActionSource aas;
            //  = new AssetActionSource(
            //     Id=TestUtility.getFakeId(Schema.AssetActionSource.getSObjectType()),
            //     TransactionDate=input.transactionDate,
            //     StartDate=input.startDate,
            //     EndDate=input.endDate,
            //     ProductAmount=input.productAmount,
            //     EstimatedTax=input.estimatedTax,
            //     ActualTax=input.actualTax,
            //     AdjustmentAmount=input.adjustmentAmount
            // );
            if(input instanceof Tranquility.ReferencedAssetActionSourceInput) {
                // aas.ReferenceEntityItemId = ((Tranquility.ReferencedAssetActionSourceInput) input).referenceEntityItem;
                aas = new AssetActionSource(
                    Id=TestUtility.getFakeId(Schema.AssetActionSource.getSObjectType()),
                    TransactionDate=input.transactionDate,
                    StartDate=input.startDate,
                    EndDate=input.endDate,
                    ProductAmount=input.productAmount,
                    EstimatedTax=input.estimatedTax,
                    ActualTax=input.actualTax,
                    AdjustmentAmount=input.adjustmentAmount,
                    ReferenceEntityItemId = ((Tranquility.ReferencedAssetActionSourceInput) input).referenceEntityItem
                );
            } else {
                aas = new AssetActionSource(
                    Id=TestUtility.getFakeId(Schema.AssetActionSource.getSObjectType()),
                    TransactionDate=input.transactionDate,
                    StartDate=input.startDate,
                    EndDate=input.endDate,
                    ProductAmount=input.productAmount,
                    EstimatedTax=input.estimatedTax,
                    ActualTax=input.actualTax,
                    AdjustmentAmount=input.adjustmentAmount,
                    ExternalReference = ((Tranquility.NonReferencedAssetActionSourceInput) input).externalReference,
                    ExternalReferenceDataSource = ((Tranquility.NonReferencedAssetActionSourceInput) input).ExternalReferenceDataSource
                );
            }
            resp.assetActionSources.add(aas);
        }
        List<Tranquility.AssetStatePeriodInput> reqAsps;
        if(assetReq instanceof Tranquility.CancelAssetRequest) {
            reqAsps = new List<Tranquility.AssetStatePeriodInput>{
                ((Tranquility.CancelAssetRequest) assetReq).assetStatePeriod
            };
        } else {
            reqAsps = ((Tranquility.UpsertAssetRequest) assetReq).assetStatePeriods;
        }
        for(Tranquility.AssetStatePeriodInput input : reqAsps) {
            AssetStatePeriod asp = new AssetStatePeriod(
                Id=TestUtility.getFakeId(Schema.AssetStatePeriod.getSObjectType()),
                StartDate=input.startDate,
                EndDate=input.endDate,
                Quantity=input.quantity,
                Mrr=input.mrr,
                Amount=input.amount
            );
            resp.assetStatePeriods.add(asp);
        }

        HTTPResponse httpResp = new HTTPResponse();
        httpResp.setStatusCode(200);
        httpResp.setHeader('Content-Type', 'application/json');
        httpResp.setBody(JSON.serialize(resp));
        if(Test.isRunningTest()) {
            System.debug('MOCK RESP: ' + httpResp);
        }
        return httpResp;
    }

    private class FindASPsByAssetId implements StagedDatabase.QueryFunction {
        private String assetId;

        public FindASPsByAssetId (String assetId) {
            this.assetId = assetId;
        }

        public Boolean match (StagedRecord rec) {
            return rec.getType() == 'AssetStatePeriod' && rec.get('AssetId') == this.assetId;
        }
    }
}