public virtual class TimePeriod implements Periodic {
    public Datetime startDate;
    public Datetime endDate;
    public List<Id> sourceIds = new List<Id>();
    private Map<String,Double> internalValues = new Map<String,Double>();
    private Map<String,Double> values {
        get {
            return this.getValues();
        }
        set {
            this.setValues(value);
        }
    }

    // public TimePeriod (){}

    // public TimePeriod (Datetime startDate, Datetime endDate, List<Id> sourceIds) {
    //     this.startDate = startDate;
    //     this.endDate = endDate;
    //     this.sourceIds = sourceIds;
    // }

    public TimePeriod (Datetime startDate, Datetime endDate, List<Id> sourceIds, Map<String,Double> values) {
        this.startDate = startDate;
        this.endDate = endDate;
        this.sourceIds = sourceIds;
        this.values = values;
    }

    // public TimePeriod (Periodic asp) {
    //     this.startDate = asp.getStart();
    //     this.endDate = asp.getEnd();
    //     Map<String,Double> vals = asp.getValues();
    //     for (String key : vals.keySet()) {
    //         this.values.put(key, vals.get(key));
    //     }
    // }
    
    // public TimePeriod (AssetStatePeriod asp) {
    //     this.startDate = asp.StartDate;
    //     this.endDate = asp.EndDate;
    //     this.values.put('mrr', asp.Mrr);
    //     this.values.put('quantity', asp.Quantity);
    //     this.values.put('amount', asp.Amount);
    // }

    // public TimePeriod (AssetStatePeriod asp, List<Id> sourceIds) {
    //     this.startDate = asp.StartDate;
    //     this.endDate = asp.EndDate;
    //     if(sourceIds != null) {
    //         this.sourceIds.addAll(sourceIds);
    //     }
    //     this.values.put('mrr', asp.Mrr);
    //     this.values.put('amount', asp.Amount);
    //     this.values.put('quantity', asp.Quantity);
    // }
    public TimePeriod (Periodic asp, List<Id> sourceIds) {
        this.startDate = asp.getStart();
        this.endDate = asp.getEnd();
        if(sourceIds != null) {
            this.sourceIds.addAll(sourceIds);
        }
        Map<String,Double> vals = asp.getValues();
        for (String key : vals.keySet()) {
            this.values.put(key, vals.get(key));
        }
    }

    public Datetime getStart(){
        return this.startDate;
    }
    public Datetime getEnd() {
        return this.endDate;
    }
    public void setStart(Datetime startDate){
        this.startDate = startDate;
    }
    public void setEnd(Datetime endDate) {
        this.endDate = endDate;
    }

    // public virtual Map<String,Double> getValues(Datetime startDate, Datetime endDate) {
    public virtual Map<String,Double> getValues() {
        return this.internalValues;
    }

    public virtual void setValue(String key, Double val) {
        this.internalValues.put(key, val);
    }

    public virtual void setValues(Map<String,Double> valMap) {
        this.internalValues = valMap;
    }

    // public void setValue(String key, Double val) {
    //     this.values.put(key, val);
    // }

    // public Double getValue(String key) {
    //     return this.values.get(key);
    // }

    public Boolean equals (Object obj) {
        return (obj instanceof Periodic) && ((Periodic) obj).getStart() == this.startDate && ((Periodic) obj).getEnd() == this.endDate;
    }

    // public Boolean hasValue(String key) {
    //     return this.values.containsKey(key);
    // }

    // public static AssetStatePeriod toAssetStatePeriod(Periodic period) {
    //     Map<String,Double> values = period.getValues();
    //     return new AssetStatePeriod(
    //         StartDate = period.getStart(),
    //         EndDate = period.getEnd(),
    //         Mrr = values.get('mrr'),
    //         Amount = values.get('amount'),
    //         Quantity = values.get('quantity')
    //     );
    // }

    // public AssetStatePeriod toAssetStatePeriod() {
    //     return toAssetStatePeriod(this);
    // }

    public static List<Periodic> normalize(List<Periodic> periods) {
        return normalize(periods, new String[]{});
    }

    // public static List<AssetStatePeriod> normalize(List<AssetStatePeriod> periods) {
    //     return normalize(periods, new String[]{});
    // }

    // public static List<AssetStatePeriod> normalize (List<AssetStatePeriod> periods, String[] preserveValues) {
    //     List<TimePeriod> input = new List<TimePeriod>();
    //     for (AssetStatePeriod asp : periods) {
    //         input.add(new TimePeriod(asp));
    //     }
    //     List<AssetStatePeriod> output = new List<AssetStatePeriod>();
    //     for (Periodic resultPeriod : normalize(input, preserveValues)) {
    //         output.add(toAssetStatePeriod(resultPeriod));
    //     }
    //     return output;
    // }

    public static List<Periodic> normalize (List<Periodic> periods, String[] preserveValues) {
        return normalize(periods, preserveValues, null, null);
    }

    public static List<Periodic> normalize (List<Periodic> periods, String[] preserveValues, Type type) {
        return normalize(periods, preserveValues, null, type);
    }

    public static List<Periodic> normalize (List<Periodic> periods, Map<String,Double> valuesOverride, Type type) {
        return normalize(periods, new List<String>(valuesOverride.keySet()), valuesOverride, type);
    }

    public static List<Periodic> normalize (List<Periodic> periods, String[] preserveValues, Map<String,Double> valuesOverride, Type type) {
        List<Datetime> dates = new List<Datetime>();
        for (Periodic period : periods) {
            if(!dates.contains(period.getStart())) {
                dates.add(period.getStart());
            }
            Datetime periodEnd = period.getEnd();
            if(periodEnd.timeGmt() == Time.newInstance(23,59,59,0)) {
                Datetime boundary = periodEnd.addSeconds(1);
                if(!dates.contains(boundary)) {
                    dates.add(boundary);
                }
            } else if(!dates.contains(periodEnd)) {
                dates.add(periodEnd);
            }
        }
        dates.sort();
        // System.debug('STARTING PERIODS:' + JSON.serialize(periods));
        // System.debug('SORTED DATES:' + JSON.serialize(dates));
        List<Periodic> normalized = new List<Periodic>();
        for(Integer i = 0; i < dates.size() - 1; i++) {
            Datetime startDate = dates.get(i);
            Datetime endDate = dates.get(i+1).addSeconds(-1);
            // if(i < dates.size() - 2) {
                // skip this for the 2nd to last date (last period)
                // endDate = endDate.addSeconds(-1);
            // }
            List<Id> sources = new List<Id>();
            Map<String,Double> values = new Map<String,Double>();
            Boolean hasPeriod = false;
            Map<String,Double> mergedValues = new Map<String,Double>();
            for(Periodic period : periods) {
                if(period.getStart() <= startDate && period.getStart() < endDate && period.getEnd() >= endDate && period.getEnd() > startDate) {
                    if(!hasPeriod) {
                        // first period
                        hasPeriod = true;
                        values = period.getValues().clone();
                    }
                    if(period instanceof TimePeriod) {
                        sources.addAll(((TimePeriod) period).sourceIds);
                    }
                    mergedValues = PWUtils.sumEntries(mergedValues, period.getValues(), preserveValues);
                }
            }
            if(!hasPeriod) {
                // continue;
            }
            for (String key : mergedValues.keySet()){
                values.put(key, mergedValues.get(key));
            }
            if(type != null) {
                Periodic newPeriod = (Periodic) type.newInstance();
                // System.debug(String.valueOf(newPeriod));
                newPeriod.setStart(startDate);
                newPeriod.setEnd(endDate);
                newPeriod.setValues(values);
                normalized.add(newPeriod);
            } else {
                normalized.add(new TimePeriod(startDate, endDate, sources, values));
            }
        }
        // If a period is unchanged, just include the original period
        List<Periodic> finalPeriods = new List<Periodic>();
        for(Periodic period : normalized) {
            Boolean matched = false;
            for (Periodic existingPeriod : periods) {
                if(period.equals(existingPeriod)) {
                    // System.debug('MAINTAINING EXISTING PERIOD');
                    matched = true;
                    finalPeriods.add(existingPeriod);
                    break;
                }
            }
            if(!matched) {
                // System.debug('NEW PERIOD CREATED');
                // System.debug(JSON.serialize(period));
                finalPeriods.add(period);
            }
        }
        if(valuesOverride != null) {
            for (Periodic period : finalPeriods) {
                for (String key : valuesOverride.keySet()) {
                    period.setValue(key, valuesOverride.get(key));
                }
            }
        }
        
        return finalPeriods;
    }

}