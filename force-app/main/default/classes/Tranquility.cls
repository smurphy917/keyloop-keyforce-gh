global class Tranquility {

    static Http http = new Http();
    public static String namedCredential = 'Salesforce';
    static Boolean sendRequests = true;

    global class GenerateResult {
        public OrderItem oi;
        public Asset asset;
        public Double mrrChange;
        public Double amount;
        public Double quantityChange;
        public AssetStatePeriodInput newPeriod;
        public Boolean assetCreated;
        public AssetRequest request;
    }

    public class CancelResult {
        public Asset asset;
    }

    public class AssetActionInput {
        public String category;
        public Datetime actionDate;
        public double quantityChange;
        public double mrrChange;
        public double amount;

        // public AssetActionInput(AssetAction aa) {
        //     this.category = aa.CategoryEnum;
        //     this.actiondate = aa.ActionDate;
        //     this.quantityChange = aa.QuantityChange;
        //     this.mrrChange = aa.MrrChange;
        //     this.amount = aa.Amount;
        // }

        public AssetActionInput(StagedAssetAction aa) {
            this.category = aa.getCategoryString();
            this.actionDate = aa.ActionDate;
            this.quantityChange = aa.QuantityChange;
            this.mrrChange = aa.MrrChange;
            this.amount = aa.Amount;
        }

        public AssetActionInput() {}
    }

    public virtual class AssetActionSourceInput {

        public Datetime transactionDate;
        public Datetime startDate;
        public Datetime endDate;
        public double quantity;
        public double productAmount;
        public double estimatedTax;
        public double actualTax;
        public double adjustmentAmount;

        // public static AssetActionSourceInput fromAssetActionSource(AssetActionSource aas) {
        //     AssetActionSourceInput result;
        //     if(aas.ReferenceEntityItemId != null) {
        //         result = new ReferencedAssetActionSourceInput();
        //         ((ReferencedAssetActionSourceInput) result).referenceEntityItem = aas.ReferenceEntityItemId;
        //     } else {
        //         result = new NonReferencedAssetActionSourceInput();
        //         ((NonReferencedAssetActionSourceInput) result).externalReference = aas.ExternalReference;
        //         ((NonReferencedAssetActionSourceInput) result).externalReferenceDataSource = aas.ExternalReferenceDataSource;
        //     }
        //     result.transactionDate = aas.TransactionDate;
        //     result.startDate = aas.StartDate;
        //     result.endDate = aas.EndDate;
        //     result.quantity = aas.Quantity;
        //     result.productAmount = aas.ProductAmount;
        //     result.estimatedTax = aas.EstimatedTax;
        //     result.actualTax = aas.ActualTax;
        //     result.adjustmentAmount = aas.AdjustmentAmount;
        //     return result;
        // }
    }

    public class NonReferencedAssetActionSourceInput extends AssetActionSourceInput {
        public String externalReference;
        public String externalReferenceDataSource;

        public NonReferencedAssetActionSourceInput() {}
        public NonReferencedAssetActionSourceInput(AssetActionSource aas) {
            this.externalReference = aas.ExternalReference;
            this.externalReferenceDataSource = aas.ExternalReferenceDataSource;
        }
        
        // public NonReferencedAssetActionSourceInput(AssetActionSource aas) {
        //     this.transactionDate = aas.TransactionDate;
        //     this.startDate = aas.StartDate;
        //     this.endDate = aas.EndDate;
        //     this.quantity = aas.Quantity;
        //     this.productAmount = aas.ProductAmount;
        //     this.estimatedTax = aas.EstimatedTax;
        //     this.actualTax = aas.ActualTax;
        //     this.adjustmentAmount = aas.AdjustmentAmount;
        //     this.externalReference = aas.ExternalReference;
        //     this.externalReferenceDataSource = aas.ExternalReferenceDataSource;
        // }
    }

    public class ReferencedAssetActionSourceInput extends AssetActionSourceInput {
        public Id referenceEntityItem;

        public ReferencedAssetActionSourceInput() {}
        
        public ReferencedAssetActionSourceInput(AssetActionSource aas) {
            this.transactionDate = aas.TransactionDate;
            this.startDate = aas.StartDate;
            this.endDate = aas.EndDate;
            this.quantity = aas.Quantity;
            this.productAmount = aas.ProductAmount;
            this.estimatedTax = aas.EstimatedTax;
            this.actualTax = aas.ActualTax;
            this.adjustmentAmount = aas.AdjustmentAmount;
            this.referenceEntityItem = aas.ReferenceEntityItemId;
        }
    }

    public class AssetStatePeriodInput implements Comparable {
        public Datetime startDate;
        public Datetime endDate;
        public double quantity;
        public double mrr;
        public double amount;

        public AssetStatePeriodInput() {}

        // public AssetStatePeriodInput(AssetStatePeriod asp) {
        //     this.startDate = asp.StartDate;
        //     this.endDate = asp.EndDate;
        //     this.quantity = asp.Quantity;
        //     this.mrr = asp.Mrr;
        //     this.amount = asp.Amount;
        // }

        public AssetStatePeriodInput(Periodic period) {
            this.startDate = period.getStart();
            this.endDate = period.getEnd();
            Map<String,Double> values = period.getValues();
            if(values.containsKey('quantity')) {
                this.quantity = values.get('quantity');
            }
            if(values.containsKey('mrr')) {
                this.mrr = values.get('mrr');
            }
            if(values.containsKey('amount')) {
                this.amount = values.get('amount');
            }
        }

        // public Boolean equals (Object obj) {
        //     return obj instanceof AssetStatePeriodInput && this.startDate == ((AssetStatePeriodInput) obj).startDate && this.endDate == ((AssetStatePeriodInput) obj).endDate;
        // }

        // public AssetStatePeriod toAssetStatePeriod() {
        //     return new AssetStatePeriod(
        //         StartDate=this.startDate,
        //         EndDate=this.endDate,
        //         Quantity=this.quantity,
        //         Mrr=this.mrr,
        //         Amount=this.amount
        //     );
        // }

        public Integer compareTo(Object obj) {
            Datetime rStart = ((AssetStatePeriodInput) obj).startDate;
            if(this.startDate == null || rStart == null) {
                return null;
            }
            if(this.startDate < rStart) {
                return -1;
            } else if (this.startDate == rStart) {
                return 0;
            } else if(this.startDate > rStart) {
                return 1;
            }
            return null;
        }
    }

    public class AssetServiceResponse {
        public Asset asset;
        public AssetAction assetAction;
        public List<AssetActionSource> assetActionSources;
        public List<AssetStatePeriod> assetStatePeriods;
        public AssetServiceResponse (HttpResponse response) {
            AssetServiceResponse r = (AssetServiceResponse) JSON.deserialize(response.getBody(), AssetServiceResponse.class);
            this.asset = r.asset;
            this.assetAction = r.assetAction;
            this.assetActionSources = r.assetActionSources;
            this.assetStatePeriods = r.assetStatePeriods;
        }
        public AssetServiceResponse(){
            this.assetActionSources = new List<AssetActionSource>();
            this.assetStatePeriods = new List<AssetStatePeriod>();
        }
    }

    public class SerializableRequest {
        public integer timeout;
        public String method;
        public Map<String,String> headers = new Map<String,String>();
        public String path;
        public String host;
        public String endpoint {
            get {
                return this.host + this.path;
            } set {
                this.host = value.substringBefore('/');
                this.path = '/' + value.substringAfter('/');
            }
        }
        public String body;
        public String action;
        public Integer complexity;

        public SerializableRequest(){}
        public SerializableRequest(HttpRequest request) {
            this.method = request.getMethod();
            this.endpoint = request.getEndpoint();
            this.body = request.getBody();
            List<String> commonHeaders = new List<String>{
                'Content-Type',
                'Accept',
                'Authorization'
            };
            for (String key : commonHeaders) {
                String headerVal = request.getHeader(key);
                if(headerVal != null) {
                    this.headers.put(key, headerVal);
                }
            }
        }

        public void setTimeout(integer timeout){
            this.timeout = timeout;
        }
        public void setMethod(String method){
            this.method = method;
        }
        public void setHeader(String key, String val) {
            this.headers.put(key, val);
        }
        public void setEndpoint(String endpoint) {
            this.endpoint = endpoint;
        }
        public void setBody(String body) {
            this.body = body;
        }
        public void setAction(String action) {
            this.action = action;
        }
        public HttpRequest toRequest() {
            return this.toRequest(null);
        }
        public HttpRequest toRequest(String namedCredential) {
            HttpRequest req = new HttpRequest();
            if(this.timeout != null) {
                req.setTimeout(this.timeout);
            }
            req.setMethod(this.method);
            for(String key : this.headers.keySet()) {
                req.setHeader(key, this.headers.get(key));
            }
            if(namedCredential == null) {
                req.setEndpoint(this.endpoint);
            } else {
                req.setEndpoint('callout:' + namedCredential + this.path);
            }
            req.setBody(this.body);
            return req;
        }
    }

    public abstract class AssetRequest {
        private List<String> excludedProperties = new List<String>();
        private String sessionId;
        public AssetActionInput assetAction = new AssetActionInput();
        public List<AssetActionSourceInput> assetActionSources = new List<AssetActionSourceInput>();

        public String toJSON() {
            Map<String,Object> filtered = new Map<String,Object>();
            Map<String,Object> entries = (Map<String,Object>) JSON.deserializeUntyped(JSON.serialize(this));
            for (String key : entries.keyset()) {
                if(!this.excludedProperties.contains(key)) {
                    filtered.put(key, entries.get(key));
                }
            }
            // Remove null keys from asset action source input
            for (Integer i = 0; i < this.assetActionSources.size(); i++) {
                Map<String, Object> aas = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(this.assetActionSources.get(i)));
                for(String key : aas.keyset()) {
                    if(aas.get(key) == null) {
                        aas.remove(key);
                    }
                }
                ((List<Object>) filtered.get('assetActionSources')).set(i, aas);
            }
            // filtered.put('assetActionSources', aasEntries);
            return JSON.serialize(filtered);
        }

        private void initExclusions() {
            this.excludedProperties.add('excludedProperties');
            this.excludedProperties.add('sessionId');
            this.excludedProperties.add('currentAssetStatePeriods');
            this.excludedProperties.add('aspOverflow');
        }

        public AssetRequest(){
            // this.sessionId = UserInfo.getSessionId();
            initExclusions();
        }

        public abstract AssetServiceResponse send();

        public abstract AssetManagementProcessTask generateTask();

        public Integer getComplexity() {
            Integer aspComplexity = 0;
            if(this instanceof UpsertAssetRequest) {
                aspComplexity = ((UpsertAssetRequest) this).assetStatePeriods.size() * 3;
            }
            return this.assetActionSources.size() + aspComplexity;
        }

        public SerializableRequest prepareRequest (String action, ID assetId) {
            // do send
            String method;
            String path = '/services/data/v56.0/asset-management/assets';
            // String endpoint = URL.getOrgDomainURL().toExternalForm() + '/services/data/v54.0/asset-management/assets';
            // String endpoint = 'callout:Salesforce/services/data/v54.0/asset-management/assets';
            switch on action {
                when 'generate' {
                    method = 'POST';
                    path += '/actions/' + action;
                }
                when 'change' {
                    System.assertNotEquals(null, assetId, 'Asset id is required for change');
                    method = 'POST'; // ...really seems like it should be PATCH :/
                    path += '/' + assetId + '/actions/' + action;
                }
                when 'cancel' {
                    method = 'POST';
                    path += '/' + assetId + '/actions/' + action;
                }
            }
            SerializableRequest req = new SerializableRequest();
            req.setTimeout(120000);
            // req.setEndpoint(endpoint);
            req.setMethod(method);
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            if(namedCredential != null) {
                req.setEndpoint('callout:' + namedCredential + path);
            } else {
                req.setEndpoint(URL.getOrgDomainURL().toExternalForm() + path);
                req.setHeader('Authorization', 'OAuth ' + UserInfo.getSessionId());
            }
            req.setBody(this.toJSON());
            req.setAction(action);
            req.complexity = this.getComplexity();
            return req;
        }
        
        public AssetServiceResponse sendAction(String action, ID assetId) {
            HttpRequest req = this.prepareRequest(action, assetId).toRequest();
            System.debug('Sending ' + action + ' request...');
            try {
                HttpResponse resp = http.send(req);
                Integer statusCode = resp.getStatusCode();
                if(statusCode >= 200 && statusCode < 300) {
                    System.debug('Successful ' + action + ' response');
                    return new AssetServiceResponse(resp);
                }
                else {
                    throw new TranquilityException('Server returned error: ' + resp.getBody() + '\nEndpoint: ' + req.getEndpoint() + '\nRequest Body: ' + req.getBody());
                }
            } catch (Exception e) {
                throw new TranquilityException('Error in calling API [' + e.getMessage() + '].\nEndpoint: ' + req.getEndpoint() + '\nRequest Body: ' + req.getBody());
            }
        }

        public AssetManagementProcessTask generateTaskAction (String action, ID assetId) {
            SerializableRequest req = this.prepareRequest(action, assetId);
            return new AssetManagementProcessTask(req);
        }
    }

    public abstract class UpsertAssetRequest extends AssetRequest {
        public List<AssetStatePeriodInput> assetStatePeriods = new List<AssetStatePeriodInput>();
        public List<AssetStatePeriodInput> aspOverflow;
        
        public virtual void addPeriod(AssetStatePeriodInput asp) {
            this.assetStatePeriods.add(asp);
        }
        // public virtual void addPeriod(AssetStatePeriod asp) {
        //     this.addPeriod(new AssetStatePeriodInput(asp));
        // }
        public virtual void addPeriod(Periodic asp) {
            this.addPeriod(new AssetStatePeriodInput(asp));
        }

        // public Asset getAsset(List<String> fields) {
        //     if(this instanceof GenerateAssetRequest) {
        //         return new Asset(
        //             AccountId=((GenerateAssetRequest)this).accountId,
        //             Name=((GenerateAssetRequest)this).assetName,
        //             Product2Id=((GenerateAssetRequest)this).productId,
        //             CurrencyIsoCode=((GenerateAssetRequest)this).currencyIsoCode,
        //             Aggregate_Asset__c=null
        //         );
        //     } else {
        //         return Database.query(String.format(
        //             'SELECT {0} FROM Asset WHERE Id=\'\'{1}\'\'',
        //             new String[]{
        //                 String.join(fields,','),
        //                 ((ChangeAssetRequest)this).assetId
        //             }
        //         ));
        //     }
        // }

        // public UpsertAssetRequest() {
        //     super();
        // }
    }

    public class GenerateAssetRequest extends UpsertAssetRequest {
        public ID accountId;
        public String assetName;
        public ID productId;
        public String currencyIsoCode;

        public GenerateAssetRequest (StagedAsset a) {
            this.accountId = a.AccountId;
            this.assetName = a.Name;
            this.productId = a.Product2Id;
            this.currencyIsoCode = a.CurrencyIsoCode;
            Integer aspCount = 0;
            for (StagedAssetStatePeriod asp : a.AssetStatePeriods) {
                this.addPeriod(asp);
                aspCount++;
                if(aspCount >= 10) {
                    this.aspOverflow = Tranquility.fromList((List<StagedAssetStatePeriod>) PWUtils.slice(a.AssetStatePeriods,10));
                    break;
                }
            }
            for (StagedAssetAction aa : a.AssetActions) {
                if(aa.stagedFor == StagedRecord.StagedAction.InsertAction) {
                    Integer count = 0;
                    this.assetAction = new AssetActionInput(aa);
                    for (AssetActionSource aas : aa.AssetActionSources) {
                        if(this.assetActionSources.size() < 10) {
                            if(aas.ReferenceEntityItemId != null) {
                                this.assetActionSources.add(new ReferencedAssetActionSourceInput(aas));
                            } else if (aas.ExternalReference != null) {
                                this.assetActionSources.add(new NonReferencedAssetActionSourceInput(aas));
                            } else {
                                throw new TranquilityException('Asset Action Source type not recognised.');
                            }
                        }
                    }
                }
            }
        }

        public override AssetManagementProcessTask generateTask() {
            return this.generateTaskAction('generate', null);
        }

        public override AssetServiceResponse send() {
            return this.sendAction('generate', null);
        }
    }

    public inherited sharing class ChangeAssetRequest extends UpsertAssetRequest {
        public Id assetId;
        private List<AssetStatePeriodInput> currentAssetStatePeriods;

        // public List<AssetStatePeriodInput> assetStatePeriods = new List<AssetStatePeriodInput>();
        // public ChangeAssetRequest(Id assetId){
        //     this.assetId = assetId;
        //     this.init();
        // }

        //public ChangeAssetRequest(Id assetId) {
        //    this.assetId = assetId;
        //    this.init();
        //}

        public ChangeAssetRequest(StagedAsset a) {
            this.assetId = a.Id;
            Integer aspCount = 0;
            for(StagedAssetStatePeriod asp : a.AssetStatePeriods) {
                this.assetStatePeriods.add(new AssetStatePeriodInput(asp));
                aspCount++;
                if(aspCount >= 10) {
                    break;
                }
            }
            for(StagedAssetAction aa : a.AssetActions) {
                if(aa.stagedFor == StagedRecord.StagedAction.InsertAction && aa.CategoryEnum != StagedAssetAction.Category.IGNORE) {
                    this.assetAction = new AssetActionInput(aa);
                    for(AssetActionSource aas : aa.AssetActionSources) {
                        this.assetActionSources.add(new ReferencedAssetActionSourceInput(aas));
                    }
                }
            }
        }

        public ChangeAssetRequest(UpsertAssetRequest req, String assetId) {
            System.assertNotEquals(null, req.aspOverflow,'No further periods to update.');
            this.assetId = assetId;
            this.assetStatePeriods.add(req.assetStatePeriods[9]);
            if(req.aspOverflow.size() > 9) {
                this.assetStatePeriods.addAll((List<AssetStatePeriodInput>) PWUtils.slice(req.aspOverflow,0,9));
                this.aspOverflow = (List<AssetStatePeriodInput>) PWUtils.slice(req.aspOverflow,9);
            } else {
                this.assetStatePeriods.addAll(req.aspOverflow);
            }
            this.assetAction = new AssetActionInput(); //req.assetAction;
            this.assetAction.actionDate = Datetime.now();
            this.assetAction.amount = 0.0;
            this.assetAction.category = 'Other';
            this.assetAction.mrrChange = 0.0;
            this.assetAction.quantityChange = 0.0;
            this.assetActionSources = new List<AssetActionSourceInput>{
                new NonReferencedAssetActionSourceInput(
                    new AssetActionSource(
                        ExternalReference = 'Creation of additional periods beyond limit',
                        ExternalReferenceDataSource = 'Internally generated'
                    )
                )
            };
        }

        // private void init() {
        //     List<AssetStatePeriod> asps = [SELECT StartDate, EndDate, Quantity, Mrr, Amount FROM AssetStatePeriod WHERE AssetId = :this.assetId WITH SECURITY_ENFORCED ORDER BY StartDate ASC];
        //     for (AssetStatePeriod asp : asps) {
        //         AssetStatePeriodInput aspi = new AssetStatePeriodInput(asp);
        //         this.assetStatePeriods.add(aspi);
        //     }
        //     this.currentAssetStatePeriods = this.assetStatePeriods;
        // }

        // public Boolean periodsChanged() {
        //     if(this.currentAssetStatePeriods.size() != this.assetStatePeriods.size()) {
        //         return true;
        //     }
        //     for (AssetStatePeriodInput asp : this.currentAssetStatePeriods) {
        //         Integer matchIdx = this.assetStatePeriods.indexOf(asp);
        //         if(matchIdx == -1) {
        //             System.debug('ASP: ' + asp);
        //             System.debug('List: ' + this.assetStatePeriods);
        //             System.debug('START: ' + (asp.startDate == this.assetStatePeriods[0].startDate));
        //             System.debug('END: ' + (asp.endDate == this.assetStatePeriods[0].endDate));
        //             return true;
        //         } else {
        //             AssetStatePeriodInput matched = this.assetStatePeriods[matchIdx];
        //             if(matched.amount != asp.amount || matched.mrr != asp.mrr) {
        //                 return true;
        //             }
        //         }
        //     }
        //     return false;
        // }

        // public override void addPeriod(AssetStatePeriodInput newAsp) {
        //     List<AssetStatePeriodInput> newASPs = new List<AssetStatePeriodInput>();
        //     for (AssetStatePeriodInput asp : this.assetStatePeriods) {
        //         Boolean addNew = false;
        //         if(asp.startDate < newAsp.startDate && asp.endDate > newAsp.startDate) {
        //             // new ASP starts before this ASP ends
        //             asp.endDate = newAsp.startDate.addSeconds(-1);// end-date this ASP one sec before new ASP starts
        //             addNew = true;
        //         }else if (asp.startDate > newAsp.startDate && asp.startDate < newAsp.endDate) {
        //             // this ASP starts before new ASP ends
        //             System.debug(asp.startDate + ' > ' + newAsp.startDate + ' && ' + asp.startDate + ' < ' + newAsp.endDate);
        //             asp.endDate = newAsp.endDate + 1;
        //         } else if (asp.startDate >= newAsp.startDate && asp.endDate <= newAsp.endDate) {
        //             // this ASP is wholly replaced by the new ASP
        //             System.debug('Current ASP replaced with: ' + newAsp);
        //             newASPs.add(newAsp);
        //             continue; // to avoid adding asp
        //         }
        //         System.debug('Existing ASP kept: ' + asp);
        //         newASPs.add(asp);
        //         if(addNew) {
        //             System.debug('New ASP added: ' + newAsp);
        //             newASPs.add(newAsp);
        //         }
        //     }
        //     this.assetStatePeriods = newASPs;
        // }

        // public AssetStatePeriodInput getStateForTime(Datetime d) {
        //     for(AssetStatePeriodInput asp : this.assetStatePeriods) {
        //         if(asp.startDate <= d && asp.endDate >= d) {
        //             return asp;
        //         }
        //     }
        //     return null;
        // }

        public List<AssetStatePeriodInput> getCurrentPeriods(){
            return this.currentAssetStatePeriods;
        }

        public override AssetManagementProcessTask generateTask() {
            return this.generateTaskAction('change', this.assetId);
        }

        public override AssetServiceResponse send() {
            return this.sendAction('change', this.assetId);
        }

        public SerializableRequest prepareRequest() {
            return this.prepareRequest('change', this.assetId);
        }
    }

    public class CancelAssetRequest extends AssetRequest {
        public ID assetId;
        public AssetStatePeriodInput assetStatePeriod = new AssetStatePeriodInput();

        // public CancelAssetRequest(ID assetId){
        //     this.assetId = assetId;
        //     this.excludedProperties.add('assetId');
        // }

        public CancelAssetRequest(ID assetId) {
            this.assetId = assetId;
            this.excludedProperties.add('assetId');
        }

        public override AssetManagementProcessTask generateTask() {
            return this.generateTaskAction('cancel', this.assetId);
        }

        public override AssetServiceResponse send() {
            return this.sendAction('cancel', this.assetId);
        }
    }

    public static List<AssetStatePeriodInput> fromList(List<Periodic> periods) {
        List<AssetStatePeriodInput> asps = new List<AssetStatePeriodInput>();
        for (Periodic pd : periods) {
            asps.add(new AssetStatePeriodInput(pd));
        }
        return asps;
    }

    // Exceptions

    private class TranquilityException extends Exception {}
}