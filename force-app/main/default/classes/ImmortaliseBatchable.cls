public with sharing class ImmortaliseBatchable implements Database.Batchable<SObject>, Database.Stateful {
    public Date cutoverDate;
    public Juventas.BatchConfig config;
    public Map<String,Juventas.DataBlock> finalBlocks = new Map<String,Juventas.DataBlock>();
    public Id workingCustomerId;
    public Id workingAssetId;
    public Id workingRootAssetId;
    public Boolean workingCoTerm;
    public Decimal workingQty;
    public Datetime workingEndDate;
    public Decimal workingMaxQty;
    public Decimal workingRenewalTerm;
    public Decimal workingMrr;
    Datetime workingRootEndDate;
    public String[] fields = new String[]{
        'AssetId',
        'Asset.LifecycleEndDate',
        'Asset.Aggregate_Asset__r.AccountId',
        'Asset.Aggregate_Asset__r.RootAssetId',
        'Asset.Aggregate_Asset__r.RootAsset.LifecycleEndDate',
        'StartDate',
        'EndDate',
        'Quantity',
        'Mrr',
        'Amount',
        'Asset.Co_Terminus__c',
        'Asset.Product2.Renewal_Term__c'
    };

    public ImmortaliseBatchable (Date cutoverDate, Juventas.BatchConfig config) {
        this.cutoverDate = cutoverDate;
        this.config = config;
    }


    public Database.QueryLocator start(Database.BatchableContext ctx) {
        String dateQuery = Datetime.newInstanceGmt(this.cutoverDate, Time.newInstance(0,0,0,0)).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        String query = 'SELECT ' + String.join(this.fields, ', ') + ' FROM AssetStatePeriod';
        query += ' WHERE Asset.Status = \'Installed\' AND Asset.Aggregate_Asset__c != null AND Asset.ParentId != null AND  AssetId NOT IN (SELECT Asset__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Renewal__c = true) AND EndDate > ' + dateQuery;
        if(this.config.queryStr != null) {
            query += ' AND ' + this.config.queryStr;
        }
        query += ' ORDER BY Asset.Aggregate_Asset__r.AccountId, Asset.Aggregate_Asset__r.RootAssetId, AssetId, Asset.LifecycleEndDate, EndDate';
        if(this.config.recordLimit != null) {
            query += ' LIMIT ' + this.config.recordLimit;
        }
        System.debug('QUERY: ' + query);
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext ctx, List<AssetStatePeriod> asps) {
        System.debug(JSON.serialize(this));
        Decimal renewalDeltaQty;
        String blockKey;
        Juventas.DataBlock block;
        Date renewalStartDate;
        Date renewalEndDate;
        Boolean addToBlock;
        List<Juventas.IncrementalRenewal> incRenewals = new List<Juventas.IncrementalRenewal>();
        Juventas.IncrementalRenewal incRenewal;
        for (AssetStatePeriod asp : asps) {
            addToBlock = false;
            if(this.workingAssetId != null && asp.AssetId == this.workingAssetId && asp.Quantity < this.workingQty && asp.EndDate > cutoverDate) {
                // assetId unchanged, qty lower >> Future period for same asset with less qty >> stage partial renewal
                addToBlock = true;
                renewalStartDate =  asp.StartDate.dateGmt();
                renewalEndDate = asp.EndDate.dateGmt();
                incRenewal = new Juventas.IncrementalRenewal(
                    this.workingAssetId,
                    this.workingQty - asp.Quantity, // delta qty
                    this.workingMaxQty, // target qty (temporary)
                    (this.workingMrr - asp.Mrr) / (this.workingQty - asp.Quantity)
                );
                incRenewals.add(incRenewal);
            }
            if(this.workingAssetId != null && asp.AssetId != this.workingAssetId && this.workingCoTerm != true) {
                // assetId changed, asset not co-terminus >> Last period for asset, not aligned to root LC end date >> stage alignment renewal(s)
                addToBlock = true;
                renewalStartDate = this.workingEndDate.dateGmt().addDays(1);
                renewalEndDate = Juventas.getRenewalEndDate(renewalStartDate, this.workingRootEndDate.dateGmt(), this.workingRenewalTerm);
                renewalDeltaQty = this.workingMaxQty;
                incRenewal = new Juventas.IncrementalRenewal(
                    this.workingAssetId,
                    this.workingMaxQty, // delta qty
                    null, // target qty
                    this.workingMrr / this.workingQty
                );
                for (Juventas.IncrementalRenewal incr : incRenewals) {
                    incr.targetQuantity = this.workingMaxQty;
                }
                incRenewals = new List<Juventas.IncrementalRenewal>();
            }
            if(addToBlock){
                blockKey = this.workingRootAssetId + '|' + renewalStartDate + '|' + renewalEndDate;
                block = this.finalBlocks.get(blockKey);
                if(block == null) {
                    block = new Juventas.DataBlock(this.workingCustomerId, this.workingRootAssetId, renewalStartDate, renewalEndDate);
                    this.finalBlocks.put(blockKey, block);
                }
                block.assets.put(this.workingAssetId, incRenewal);
            }
            if(asp.AssetId != this.workingAssetId || asp.Quantity > this.workingMaxQty) {
                this.workingMaxQty = asp.Quantity;
            }
            this.workingCustomerId = asp.Asset.Aggregate_Asset__r.AccountId;
            this.workingAssetId = asp.AssetId;
            this.workingRootAssetId = asp.Asset.Aggregate_Asset__r.RootAssetId;
            this.workingCoTerm = asp.Asset.Co_Terminus__c;
            this.workingQty = asp.Quantity;
            this.workingEndDate = asp.EndDate;
            this.workingRenewalTerm = asp.Asset.Product2.Renewal_Term__c;
            this.workingRootEndDate = asp.Asset.Aggregate_Asset__r.RootAsset.LifecycleEndDate;
            this.workingMrr = asp.Mrr;
        }
    }

    public void finish(Database.BatchableContext ctx) {
        // finish last renewal
        Date renewalStartDate = this.workingEndDate.dateGmt().addDays(1);
        Date renewalEndDate = Juventas.getRenewalEndDate(renewalStartDate, this.workingRootEndDate.dateGmt(), this.workingRenewalTerm);
        Decimal renewalQty = this.workingMaxQty;
        String blockKey = this.workingRootAssetId + '|' + renewalStartDate + '|' + renewalEndDate;
        Juventas.DataBlock block = this.finalBlocks.get(blockKey);
        if(block == null) {
            block = new Juventas.DataBlock(this.workingCustomerId, this.workingRootAssetId, renewalStartDate, renewalEndDate);
            this.finalBlocks.put(blockKey, block);
        }
        block.assets.put(
            this.workingAssetId, 
            new Juventas.IncrementalRenewal(
                this.workingAssetId,
                this.workingMaxQty, // delta qty
                null // target qty
            )
        );
        
        System.enqueueJob(new JuventasQueueable(this.finalBlocks.values(), this.config));
    }
}