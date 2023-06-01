public with sharing class StagedAsset extends StagedRecord {

    List<StagedAssetStatePeriod> internalAssetStatePeriods = null;
    List<StagedAssetAction> internalAssetActions = null;
    protected String sObjectType = 'Asset';

    // PRIMARY FIELDS
    public String Name {
        get {
            return (String) this.get('Name');
        }
        set {
            this.set('Name', value);
        }
    }
    public Id Product2Id {
        get {
            return (Id) this.get('Product2Id');
        }
        set {
            this.set('Product2Id', value);
        }
    }
    public Datetime LifecycleStartDate {
        get {
            Datetime result = (Datetime) this.get('StagedLifecycleStartDate__c');
            if(result == null) {
                result = (Datetime) this.get('LifecycleStartDate');
            }
            return result;
        }
        set {
            this.set('StagedLifecycleStartDate__c', value);
        }
    }
    public Datetime LifecycleEndDate {
        get {
            Datetime result = (Datetime) this.get('StagedLifecycleEndDate__c');
            if(result == null) {
                result = (Datetime) this.get('LifecycleEndDate');
            }
            return result;
        }
        set {
            this.set('StagedLifecycleEndDate__c', value);
        }
    }
    public Id AccountId {
        get {
            return (Id) this.get('AccountId');
        }
        set {
            this.set('AccountId', value);
        }
    }
    public String RootAssetId {
        get {
            String rootId = (String) this.get('RootAssetId');
            if(rootId != null) {
                return rootId;
            } 
            return this.getRootId();
        }
    }
    public String ParentId {
        get {
            return (String) this.get('ParentId');
        }
        set {
            this.set('ParentId', value);
        }
    }
    public String CurrencyIsoCode {
        get {
            return (String) this.get('CurrencyIsoCode');
        }
        set {
            this.set('CurrencyIsoCode', value);
        }
    }

    public String Status {
        get {
            return (String) this.get('Status');
        }
        set {
            this.set('Status', value);
        }
    }

    public override SObject getRecord() {
        Map<String,Object> recordMap = (Map<String,Object>) JSON.deserializeUntyped(JSON.serialize(super.getRecord()));
        recordMap.remove('RootAssetId');
        return (SObject) JSON.deserialize(JSON.serialize(recordMap), SObject.class);
    }

    // RELATED LISTS
    public List<StagedAssetStatePeriod> AssetStatePeriods {
        get {
            if(this.internalAssetStatePeriods == null) {
                this.internalAssetStatePeriods = StagedAssetStatePeriod.fromList(
                    ((Asset) this.record).AssetStatePeriods
                );
            }
            return this.internalAssetStatePeriods;
        }
        set {
            this.internalAssetStatePeriods = value;
        }
    }
    public List<StagedAssetAction> AssetActions {
        get {
            if(this.internalAssetActions == null) {
                this.internalAssetActions = StagedAssetAction.fromList(((Asset) this.record).AssetActions);
            }
            return this.internalAssetActions;
        }
        set {
            this.internalAssetActions = value;
        }
    }

    public String getRootId() {
        StagedAsset parent;
        try {
            parent = (StagedAsset) this.getLookup('Parent');
        } catch (Exception e) {
            System.debug('INVALID PARENT - ID: ' + this.Id);
            System.debug('\tParent: ' + JSON.serialize(this.getLookup('Parent')));
            System.assert(false);
        }
        if(parent != null) {
            return parent.getRootId();
        } else {
            return this.Id;
        }
    }

    public override void setLookup(String path, StagedRecord rec) {
        if(path == 'Parent') {
            this.setReference('RootAssetId', null, true);
        }
        super.setLookup(path, rec);
    }

    public void addAssetStatePeriod (StagedAssetStatePeriod asp){
        this.AssetStatePeriods.add(asp);
        this.touch();
    }

    public void addAssetAction (AssetAction aa){
        ((Asset) this.record).AssetActions.add(aa);
        this.touch();
    }

    public StagedAsset(){
        super(new Asset());
        this.setExcludedProps();
    }
    public StagedAsset(Asset a) {
        super(a);
        this.setExcludedProps();
    }
    public StagedAsset(StagedRecord rec) {
        super(rec.record);
        this.setExcludedProps();
    }
    protected override void resetExcludedProps() {
        super.resetExcludedProps();
        this.setExcludedProps();
    }
    private void setExcludedProps() {
        this.excludedProperties.addAll(new String[]{
            'internalAssetStatePeriods',
            'internalAssetActions',
            'currentAssetAction',
            'RootAssetId'
        });
        this.childArrayProperties.addAll(new String[]{
            'AssetStatePeriods',
            'AssetActions'
        });
    }
    public Boolean isValidForAction() {
        switch on this.stagedFor {
            when UpdateAction {
                Datetime earliestCurrentStart;
                Datetime earliestUpdatedStart;
                List<StagedAssetStatePeriod> currentPeriods = new List<StagedAssetStatePeriod>();
                if(((Asset) this.record).AssetStatePeriods != null && ((Asset) this.record).AssetStatePeriods.size() > 0) {
                    currentPeriods = StagedAssetStatePeriod.fromList(((Asset) this.record).AssetStatePeriods);
                } else {
                    for (StagedAssetStatePeriod asp : this.AssetStatePeriods) {
                        if(asp.inserted != null && asp.inserted == true) {
                            currentPeriods.add(asp);
                        }
                    }
                    /*
                    for (StagedRecord rec : StagedDatabase.query(new FindInsertedASPsByAssetId(this.Id))) {
                        currentPeriods.add((StagedAssetStatePeriod) rec);
                    }
                    */
                }
                // System.debug('CURRENT ASPS: ' + JSON.serialize(currentPeriods));
                for (StagedAssetStatePeriod asp : currentPeriods) {
                    if(earliestCurrentStart == null || asp.StartDate < earliestCurrentStart) {
                        earliestCurrentStart = asp.StartDate;
                    }
                }
                for (StagedAssetStatePeriod asp : this.AssetStatePeriods) {
                    if((asp.inserted == null || asp.inserted == false) && earliestUpdatedStart == null || asp.StartDate < earliestUpdatedStart) {
                        earliestUpdatedStart = asp.StartDate;
                    }
                }
                return earliestUpdatedStart == earliestCurrentStart;
            }
        }
        return true;
    }
    public NestedObject getTree() {
        NestedObject tree = new NestedObject(this);
        for (StagedAsset a : this.getChildren()) {
            tree.addChild(a.getTree());
        }
        return tree;
    }
    public List<StagedAsset> getChildren() {
        List<StagedAsset> children = new List<StagedAsset>();
        for(StagedRecord rec : StagedDatabase.query(new FindByParentId(this.Id))) {
            StagedAsset a;
            if(rec instanceof StagedAsset) {
                a = (StagedAsset) rec;
            } else {
                a = new StagedAsset(rec);
            }
            children.add(a);
        }
        return children;
    }
    public override void initiate() {
        super.initiate();
        for(StagedAssetStatePeriod asp : this.AssetStatePeriods) {
            asp.AssetId = this.Id;
            asp.initiate();
        }
        for(StagedAssetAction aa : this.AssetActions) {
            aa.AssetId = this.Id;
            aa.initiate();
        }
    }
    private String hash(SObject record) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(
            String.join(new String[]{
                ((Asset) record).Product2Id,
                ((Asset) record).AccountId
            }, '|')
        )));
    }
    public Boolean hasCALMUpdate() {
        if(this.stagedFor == StagedRecord.StagedAction.NoAction) {
            return false;
        }
        for (StagedAssetStatePeriod asp : this.AssetStatePeriods) {
            if(asp.stagedFor != StagedRecord.StagedAction.NoAction) {
                return true;
            }
        }
        for (StagedAssetAction aa : this.AssetActions) {
            if(aa.stagedFor != StagedRecord.StagedAction.NoAction) {
                return true;
            }
        }
        return false;
    }
    public static StagedAsset copy(StagedAsset rec) {
        StagedAsset copied = (StagedAsset) JSON.deserialize(rec.toJSON(), StagedAsset.class);
        // System.debug('COPIED (Id >>> ParentId): ' + rec.Id + ' >>> ' + rec.ParentId);
        copied.Id = null;
        copied.sourceIds = new List<String>();
        return copied;
    }
    private List<Object> childArrayToJSON(String key) {
        List<Object> entries = new List<Object>();
        switch on key {
            when 'AssetStatePeriods' {
                for (StagedAssetStatePeriod asp : this.AssetStatePeriods) {
                    entries.add(
                        JSON.deserializeUntyped(asp.toJSON())
                    );
                }
            }
            when 'AssetActions' {
                if(this.AssetActions != null) {
                    for (StagedAssetAction aa : this.AssetActions) {
                        if(aa != null) {
                            entries.add(
                                JSON.deserializeUntyped(aa.toJSON())
                            );
                        } else {
                            entries.add(null);
                        }
                    }
                }
            }
        }
        return entries;
    }
    public override Boolean replaceReference(String oldId, String newId) {
        // System.debug('STAGED ASSET REPLACE REF: ' + oldId + ' -> ' + newId);
        if(oldId != null && this.ParentId == oldId) {
            // System.debug('\tREPLACING PARENT');
            this.set('ParentId', newId);
            return true;
        } else if (oldId != null && this.get('Aggregate_Asset__c') == oldId) {
            // System.debug('\tREPLACING AGG ASSET');
            this.set('Aggregate_Asset__c', newId);
            return true;
        }
        return super.replaceReference(oldId, newId);
    }
    private class FindByParentId implements StagedDatabase.QueryFunction {
        private String parentId;
        public FindByParentId(String parentId) {
            this.parentId = parentId;
        }
        public Boolean match(StagedRecord record) {
            return record.getType() == 'Asset' && record.get('ParentId') == this.parentId;
        }
    }

    private class FindInsertedASPsByAssetId implements StagedDatabase.QueryFunction {
        private String assetId;
        public FindInsertedASPsByAssetId (String assetId) {
            this.assetId = assetId;
        }
        public Boolean match (StagedRecord record) {
            return record.getType() == 'AssetStatePeriod' && record.inserted == true && ((StagedAssetStatePeriod) record).AssetId == this.assetId;
        }
    }
}