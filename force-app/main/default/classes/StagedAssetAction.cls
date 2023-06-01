public with sharing class StagedAssetAction extends StagedRecord {

    public enum Category {
        Initial_Sale,
        Upsells,
        Cross_Sells,
        Downsells,
        Cancellations,
        Other,
        Renewals,
        Terms_And_Conditions_Changes,
        IGNORE
    }

    private String internalAssetId;
    private Datetime internalActionDate;
    private Double internalAmount;
    private Category internalCategoryEnum;
    private Double internalMrrChange;
    private Double internalQuantityChange;
    private Date internalStartDate;
    private Date internalEndDate;
    public Double oneTimeAmount;
    private Double internalRecurringAmount;
    private Boolean calculating = false;
    public Boolean applied = false;
    public Boolean rollUp = true;

    private String lastChanged = null;

    public Date effectiveStartDate {
        get {
            return this.internalStartDate;
        }
        set {
            this.internalStartDate = value;
            handlePropChange();
        }
    }

    public Date effectiveEndDate {
        get {
            return this.internalEndDate;
        }
        set {
            this.internalEndDate = value;
            handlePropChange();
        }
    }

    public Double recurringAmount {
        get {
            return this.internalRecurringAmount;
        }
        set {
            this.internalRecurringAmount = value;
            this.lastChanged = 'recurringAmount';
            handlePropChange();
        }
    }

    public String AssetId {
        get {
            if(this.internalAssetId != null) {
                return this.internalAssetId;
            }
            return (String) this.get('AssetId');
        }
        set {
            this.internalAssetId = value;
        }
    }

    public Datetime ActionDate {
        get {
            if(this.internalActionDate != null) {
                return this.internalActionDate;
            }
            return (Datetime) this.get('ActionDate');
        }
        set {
            this.internalActionDate = value;
        }
    }
    public Double Amount {
        get {
            if(this.internalAmount != null) {
                return this.internalAmount;
            }
            Double calcAmount;
            if(this.recurringAmount != null) {
                calcAmount = this.recurringAmount;
            }
            if(this.oneTimeAmount != null) {
                if(calcAmount == null) {
                    calcAmount = this.oneTimeAmount;
                } else {
                    calcAmount += this.oneTimeAmount;
                }
            }
            if(calcAmount != null) {
                return calcAmount;
            }
            Double amt = (Double) this.get('Amount');
            if(amt == null) {
                return 0.0;
            }
            return amt;
        }
        set {
            this.internalAmount = value;
        }
    }
    public Category CategoryEnum {
        get {
            if(this.internalCategoryEnum != null) {
                return this.internalCategoryEnum;
            }
            return toCategory(((AssetAction) this.record).CategoryEnum);
        }
        set {
            this.internalCategoryEnum = value;
        }
    }
    public Double MrrChange {
        get {
            if(this.recurringAmount != null && this.effectiveStartDate != null && this.effectiveEndDate != null) {
                return PWUtils.unprorate(
                    this.recurringAmount, 
                    this.effectiveStartDate, 
                    this.effectiveEndDate, 
                    PWUtils.ProrationMethod.MONTHLY_DAILY, 
                    PWUtils.Period.MONTH
                );
            }
            if(this.internalMrrChange != null) {
                return this.internalMrrChange;
            }
            return (Double) this.get('MrrChange');
        }
        set {
            this.internalMrrChange = value;
            this.lastChanged = 'MrrChange';
            handlePropChange();
        }
    }
    public Double QuantityChange {
        get {
            if(this.internalQuantityChange != null) {
                return this.internalQuantityChange;
            }
            return (Double) this.get('QuantityChange');
        }
        set {
            this.internalQuantityChange = value;
        }
    }

    public static List<String> fields {
        get {
            return new String[]{
                'AssetId',
                'ActionDate',
                'Amount',
                'CategoryEnum',
                'MrrChange',
                'QuantityChange'
            };
        }
    }

    public List<AssetActionSource> AssetActionSources = new List<AssetActionSource>();

    public StagedAssetAction() {
        super(new AssetAction());
        this.setExcludedProps();
    }

    public StagedAssetAction(AssetAction aa) {
        super(aa);
        this.setExcludedProps();
    }

    private void setExcludedProps() {
        this.excludedProperties.addAll(new String[]{
            'internalAssetId',
            'internalActionDate',
            'internalAmount',
            'internalCategoryEnum',
            'internalAmount',
            'internalMrrChange',
            'internalQuantityChange',
            'internalRecurringAmount',
            'internalStartDate',
            'internalEndDate',
            'calculating',
            'lastChanged'
        });
        this.childArrayProperties.addAll(new String[]{
            'AssetActionSources'
        });
        this.overrideFields.addAll(new String[]{
            'CategoryEnum'
        });
    }

    private void handlePropChange() {
        if(this.effectiveStartDate == null || this.effectiveEndDate == null || this.calculating == true) {
            return;
        }
        this.calculating = true;
        switch on this.lastChanged {
            when 'MrrChange' {
                // calculate recurringAmount from MrrChange
                this.recurringAmount = PWUtils.prorate(
                    this.MrrChange,
                    PWUtils.Period.MONTH,
                    this.effectiveStartDate,
                    this.effectiveEndDate,
                    PWUtils.ProrationMethod.MONTHLY_DAILY
                );
            }
            when 'recurringAmount' {
                // calculate MrrChange from recurringAmount
                this.MrrChange = PWUtils.unprorate(
                    this.recurringAmount, 
                    this.effectiveStartDate,
                    this.effectiveEndDate,
                    PWUtils.ProrationMethod.MONTHLY_DAILY,
                    PWUtils.Period.MONTH
                );
            }
        }
        this.lastChanged = null;
        this.calculating = false;
    }

    protected override void resetExcludedProps() {
        super.resetExcludedProps();
        this.setExcludedProps();
    }

    public static List<StagedAssetAction> fromList (List<AssetAction> aas) {
        List<StagedAssetAction> result = new List<StagedAssetAction>();
        for (AssetAction aa : aas) {
            result.add(
                new StagedAssetAction(aa)
            );
        }
        return result;
    }

    public static List<AssetAction> toList(List<StagedAssetAction> aas) {
        List<AssetAction> result = new List<AssetAction>();
        for (StagedAssetAction aa : aas) {
            result.add(aa.toAssetAction());
        }
        return result;
    }

    public static Category toCategory(String cat) {
        try {
            return Category.valueOf(cat);
        } catch (Exception e) {
            switch on cat {
                when 'Initial Sale' {
                    return Category.Initial_Sale;
                }
                when 'Cross-Sells' {
                    return Category.Cross_Sells;
                }
                when 'Terms And Conditions Changes' {
                    return Category.Terms_And_Conditions_Changes;
                }
            }
            if(cat == null){
                return null;
            }
            throw e;
        }
    }

    public String getCategoryString() {
        if(this.CategoryEnum == null) {
            System.debug('NULL CATEGORY ACTION: ' + JSON.serialize(this));
        }
        String cat = this.CategoryEnum.name();
        switch on cat {
            when 'Initial_Sale' {
                return 'Initial Sale';
            }
        }
        return cat;
    }

    // public override String toJSON() {
    //     Map<String,Object> entries = new Map<String,Object>();
    //     entries.put('StartDate', this.StartDate);
    //     entries.put('EndDate', this.EndDate);
    //     entries.put('Quantity', this.Quantity);
    //     entries.put('Mrr', this.Mrr);
    //     entries.put('Amount', this.Amount);
    //     return JSON.serialize(entries);
    // }

    public AssetAction toAssetAction() {
        return (AssetAction) JSON.deserialize(this.toJSON(true), AssetAction.class);
    }

    public Double getRecurringPart(Date startDate, Date endDate) {
        if(this.recurringAmount == null) {
            return null;
        }
        if(startDate == this.effectiveStartDate && endDate == this.effectiveEndDate) {
            return this.recurringAmount;
        }
        return PWUtils.prorate(
            PWUtils.unprorate(
                this.recurringAmount,
                this.effectiveStartDate,
                this.effectiveEndDate,
                PWUtils.ProrationMethod.MONTHLY_DAILY,
                PWUtils.Period.MONTH
            ),
            PWUtils.Period.MONTH, 
            startDate, 
            endDate, 
            PWUtils.ProrationMethod.MONTHLY_DAILY
        );
    }

    public override Object getOverrideField(String field) {
        switch on field {
            when 'CategoryEnum' {
                return this.getCategoryString();
            }
        }
        return null;
    }

    private List<Object> childArrayToJSON(String key){
        switch on key {
            when 'AssetActionSources' {
                return this.AssetActionSources;
            }
        }
        return new List<Object>();
    }

    public static StagedAssetAction copy(StagedAssetAction rec) {
        StagedAssetAction copied = (StagedAssetAction) JSON.deserialize(rec.toJSON(), StagedAssetAction.class);
        copied.Id = null;
        return copied;
    }

    private String hash(SObject record) {
        String actionDate = null;
        if(((AssetAction) record).ActionDate != null) {
            actionDate = ((AssetAction) record).ActionDate.format();
        }
        return EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(
            String.join(new String[]{
                ((AssetAction) record).AssetId,
                actionDate
            }, '|')
        )));
    }
}