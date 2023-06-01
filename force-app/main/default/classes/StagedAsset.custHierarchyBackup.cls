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
            return (String) this.get('RootAssetId');
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

    public String Id {
        get {
            if(this.internalId != null) {
                return this.internalId;
            }
            return this.record.Id;
        }
        set {
            this.set('Id', value);
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
            'currentAssetAction'
        });
        this.childArrayProperties.addAll(new String[]{
            'AssetStatePeriods',
            'AssetActions'
        });
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
        if(this.internalId != null) {
            return this.internalId;
        }
        return EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(
            String.join(new String[]{
                ((Asset) record).Product2Id,
                ((Asset) record).AccountId
            }, '|')
        ))) + ':' + Datetime.now().getTime();
    }
    public static StagedAsset copy(StagedAsset rec) {
        return (StagedAsset) JSON.deserialize(rec.toJSON(), StagedAsset.class);
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
    private class FindByParentId implements StagedDatabase.QueryFunction {
        private String parentId;
        public FindByParentId(String parentId) {
            this.parentId = parentId;
        }
        public Boolean match(StagedRecord record) {
            return record.getType() == 'Asset' && record.get('ParentId') == this.parentId;
        }
    }
}