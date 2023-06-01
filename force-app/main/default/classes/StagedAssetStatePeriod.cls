public with sharing class StagedAssetStatePeriod extends StagedRecord implements Periodic, Comparable {

    public enum ChangeType {
        OneTime,
        Recurring
    }
    
    private String internalAssetId;
    private Datetime internalStartDate;
    private Datetime internalEndDate;
    private Decimal internalQuantity;
    private Decimal internalMrr;
    
    public Decimal oneTimeAmount = 0.0;

    public String AssetId {
        get {
            if(this.internalAssetId != null) {
                return this.internalAssetId;
            }
            return this.record == null ? null : ((AssetStatePeriod) this.record).AssetId;
        }
        set {
            this.internalAssetId = value;
            this.internalId = this.hash(this.record);
        }
    }

    public Datetime StartDate {
        get {
            if(this.internalStartDate != null) {
                return this.internalStartDate;
            }
            return this.record == null ? null : ((AssetStatePeriod) this.record).StartDate;
        }
        set {
            this.internalStartDate = value;
            this.internalId = this.hash(this.record);
            this.touch();
        }
    }

    public Datetime EndDate {
        get {
            if(this.internalEndDate != null) {
                return this.internalEndDate;
            }
            return this.record == null ? null : ((AssetStatePeriod) this.record).EndDate;
        }
        set {
            this.internalEndDate = value;
            this.internalId = this.hash(this.record);
            this.touch();
        }
    }

    public Double Quantity {
        get {
            if(this.internalQuantity == null) {
                this.internalQuantity = ((AssetStatePeriod) this.record).Quantity;
                if(this.internalQuantity == null) {
                    this.internalQuantity = 0.0;
                }
            }
            return this.internalQuantity;
        }
        set {
            this.internalQuantity = value;
            this.touch();
        }
    }
    public Decimal Mrr {
        get {
            if(this.internalMrr == null) {
                this.internalMrr = ((AssetStatePeriod) this.record).Mrr;
                if(this.internalMrr == null) {
                    this.internalMrr = 0.0;
                }
            }
            return this.internalMrr;
        }
        set {
            this.internalMrr = value;
            this.touch();
        }
    }
    public Decimal Amount {
        get {
            try {
                if(this.oneTimeAmount == null && this.Mrr == null) {
                    if(((AssetStatePeriod) this.record).Amount == null) {
                        return 0.0;
                    }
                    return ((AssetStatePeriod) this.record).Amount;
                } else if (this.Mrr == null || this.Mrr == 0.0) {
                    return this.oneTimeAmount == null ? 0.0 : this.oneTimeAmount;
                } else if (this.oneTimeAmount == null) {
                    return this.Mrr == 0.0 ? 0.0 : PWUtils.prorate(this.Mrr, PWUtils.Period.MONTH, this.StartDate.dateGmt(), this.EndDate.dateGmt(), PWUtils.ProrationMethod.MONTHLY_DAILY);
                } else if(this.StartDate == null || this.EndDate == null) {
                    return 0.0;
                }
                return this.oneTimeAmount + PWUtils.prorate(this.Mrr, PWUtils.Period.MONTH, this.StartDate.dateGmt(), this.EndDate.dateGmt(), PWUtils.ProrationMethod.MONTHLY_DAILY);
            } catch (Exception e) {
                System.debug(this);
                throw e;
            }
        }
    }

    public StagedAssetStatePeriod() {
        super(new AssetStatePeriod());
        this.setExcludedProps();
    }

    public StagedAssetStatePeriod(AssetStatePeriod asp) {
        super(asp);
        this.setExcludedProps();
        this.setAmount(((AssetStatePeriod) this.record).Amount);
    }

    public Datetime getStart() {
        return this.StartDate;
    }

    public Datetime getEnd() {
        return this.EndDate;
    }

    public void setStart(Datetime startDate) {
        this.StartDate = startDate;
    }

    public void setEnd(Datetime endDate) {
        this.EndDate = endDate;
    }

    public Map<String,Double> getValues() {
        Map<String,Double> values = new Map<String,Double>();
        values.put('mrr',this.Mrr);
        values.put('quantity', this.Quantity);
        /*
        if(startDate == null && endDate == null) {
            values.put('amount', this.Amount);
        } else {
            Datetime startDt = startDate;
            if(startDt == null) {
                startDt == this.StartDate;
            }
            Datetime endDt = endDate;
            if(endDt == null) {
                endDt = this.EndDate;
            }
            values.put('amount', PWUtils.prorate(this.Mrr, PWUtils.Period.MONTH, startDt, endDt, PWUtils.ProrationMethod.MONTHLY_DAILY) + this.oneTimeAmount);
        }
        */
        values.put('amount', this.Amount);
        values.put('oneTimeAmount', this.oneTimeAmount);
        return values;
    }
    public void setValue(String key, Double value) {
        switch on key {
            when 'mrr' {
                this.Mrr = value;
            }
            when 'quantity' {
                this.Quantity = value;
            }
            when 'oneTimeAmount' {
                this.oneTimeAmount = value;
            }
        }
    }
    public void setValues(Map<String,Double> inputValues) {
        if(inputValues.containsKey('mrr')) {
            this.Mrr = inputValues.get('mrr');
        }
        if(inputValues.containsKey('quantity')) {
            this.Quantity = inputValues.get('quantity');
        }
        // this.setAmount(inputValues.get('amount'));
        if(inputValues.containsKey('oneTimeAmount')) {
            this.oneTimeAmount = inputValues.get('oneTimeAmount');
        }
    }
    
    private void setAmount(Decimal amount) {
        if(amount != null && this.Amount != null && amount > this.Amount) {
            this.oneTimeAmount = amount - this.Amount;
        }
    }

    public void applyAmountChange (Double change, ChangeType type) {
        if(change == null || change == 0){
            return;
        }
        switch on type {
            when OneTime {
                if(this.oneTimeAmount == null) {
                    this.oneTimeAmount = change;
                    return;
                }
                this.oneTimeAmount += change;
            }
            when Recurring {
                Double amountToApply = PWUtils.unprorate(
                    change, 
                    this.StartDate.dateGmt(), 
                    this.EndDate.dateGmt(), 
                    PWUtils.ProrationMethod.MONTHLY_DAILY, 
                    PWUtils.Period.MONTH
                );
                if(this.Mrr == null) {
                    this.Mrr = amountToApply;
                    return;
                }
                this.Mrr += amountToApply;
            }
        }
    }

    private void setExcludedProps() {
        this.excludedProperties.addAll(new String[]{
            'internalStartDate',
            'internalEndDate',
            'internalQuantity',
            'internalMrr',
            'internalAssetId'
        });
    }

    protected override void resetExcludedProps() {
        super.resetExcludedProps();
        this.setExcludedProps();
    }

    public StagedAssetStatePeriod (Periodic period) {
        super(new AssetStatePeriod());
        this.setExcludedProps();
        this.StartDate = period.getStart();
        this.EndDate = period.getEnd();
        Map<String,Double> vals = period.getValues();
        this.Quantity = vals.get('quantity');
        this.Mrr = vals.get('mrr');
        // this.setAmount(vals.get('amount'));
        this.oneTimeAmount = vals.get('oneTimeAmount');
    }

    public static List<StagedAssetStatePeriod> fromList(List<Periodic> periods) {
        List<StagedAssetStatePeriod> result = new List<StagedAssetStatePeriod>();
        for (Periodic pd : periods) {
            result.add(
                new StagedAssetStatePeriod(pd)
            );
        }
        return result;
    }

    public static List<StagedAssetStatePeriod> fromList (List<AssetStatePeriod> asps) {
        List<StagedAssetStatePeriod> result = new List<StagedAssetStatePeriod>();
        for (AssetStatePeriod asp : asps) {
            result.add(
                new StagedAssetStatePeriod(asp)
            );
        }
        return result;
    }

    public static List<AssetStatePeriod> toList(List<StagedAssetStatePeriod> asps) {
        List<AssetStatePeriod> result = new List<AssetStatePeriod>();
        for (StagedAssetStatePeriod asp : asps) {
            result.add(asp.toAssetStatePeriod());
        }
        return result;
    }

    public static StagedAssetStatePeriod copy(StagedAssetStatePeriod period) {
        return (StagedAssetStatePeriod) JSON.deserialize(period.toJSON(), StagedAssetStatePeriod.class);
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

    public Boolean equals(Periodic period) {
        Boolean matched = this.StartDate == period.getStart() && this.EndDate == period.getEnd();
        if(matched) {
            // System.debug('DATE MATCHED');
            Map<String,Double> periodValues = period.getValues();
            Map<String,Double> thisValues = this.getValues();
            for(String key : periodValues.keySet()) {
                if(periodValues.get(key) != thisValues.get(key)) {
                    // System.debug('VALUE KEY NOT MATCHED: ' + key);
                    matched = false;
                    break;
                }
            }
        }
        return matched;
    }

    public AssetStatePeriod toAssetStatePeriod() {
        return (AssetStatePeriod) JSON.deserialize(this.toJSON(), AssetStatePeriod.class);
    }

    private String hash(SObject record) {
        String startDate = null;
        String endDate = null;
        String assetId = null;
        if(record != null) {
            if(((AssetStatePeriod) record).StartDate != null) {
                startDate = ((AssetStatePeriod) record).StartDate.format();
            }
            if(((AssetStatePeriod) record).EndDate != null) {
                endDate = ((AssetStatePeriod) record).EndDate.format();
            }
            if(((AssetStatePeriod) record).Assetid != null) {
                assetId = ((AssetStatePeriod) record).Assetid;
            }
        }
        if(startDate == null && this.StartDate != null) {
            startDate = this.StartDate.format();
        }
        if(endDate == null && this.EndDate != null) {
            endDate = this.EndDate.format();
        }
        if(assetId == null && this.AssetId != null) {
            assetId = this.AssetId;
        }
        return EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(
            String.join(new String[]{
                assetId,
                startDate,
                endDate
            }, '|')
        )));
    }

    /*
    public override void inserted (Id newId) {
        System.debug('ASP ISNERTED: ' + newId);
        super.inserted(newId);
        if(this.AssetId != null) {
            System.debug('\tASSET ID: ' + this.AssetId);
            StagedAsset sAsset = (StagedAsset) StagedDatabase.get(this.AssetId);
            if(sAsset != null) {
                Asset a = (Asset) sAsset.record;
                System.debug('\tAPPENDING...');
                if(a.AssetStatePeriods == null || a.AssetStatePeriods.size() == 0){
                    // Field is "not writeable" :(
                    a.AssetStatePeriods = new List<AssetStatePeriod>{this.toAssetStatePeriod()};
                } else {
                    // ... and this just doesn't work :<
                    a.AssetStatePeriods.add(this.toAssetStatePeriod());
                }
                System.debug('\t' + a.AssetStatePeriods);
                System.debug('\t' + this.toAssetStatePeriod());
                System.debug('\t' + JSON.serialize(sAsset));
                System.debug('\t' + JSON.serialize(a));
            }
        }
    }
    */

    public Integer compareTo(Object obj) {
        Datetime left = this.StartDate;
        if(!(obj instanceOf StagedAssetStateperiod)) {
            return null;
        }
        Datetime right = ((StagedAssetStatePeriod) obj).StartDate;
        if(left < right) {
            return -1;
        } else if (left == right) {
            return 0;
        } else if(left > right) {
            return 1;
        }
        return null;
    }
}