public virtual class StagedRecord extends NestedObject.Nestable {
    
    public enum StagedAction {
        UpdateAction,
        InsertAction,
        NoAction
    }
    protected String sObjectType;
    protected String[] excludedProperties = new String[] {
        'internalId',
        'sObjectType',
        'excludedProperties',
        'childArrayProperties'
        // 'Id'
    };
    private Map<String,String> idOverrides = new Map<String,String>();
    protected String[] childArrayProperties = new String[]{};
    protected String[] overrideFields = new String[]{};
    public Map<String,String> changes = new Map<String,String>();
    protected SObject record;
    public StagedAction stagedFor = StagedAction.NoAction;
    protected String internalId = null;
    public String[] sourceIds = new String[]{};
    public Exception error;
    public Boolean inserted = false;
    private Map<String, String> references = new Map<String, String>();
    protected override void setId(String value) {
        this.set('Id', value);
    }
    protected virtual void inserted(Id newId) {
        // System.debug(this.getType() + ' INSERTED');
        String prevId = this.Id;
        this.internalId = null;
        this.record.Id = newId;
        // System.debug('\t' + prevId + ' -> ' + newId);
        this.stagedFor = StagedAction.NoAction;
        this.inserted = true;
        StagedDatabase.inserted(prevId, this);
    }
    protected override String getId() {
        if(this.internalId != null) {
            return this.internalId;
        } else if(this.record != null) {
            return this.record.Id;
        }
        return null;
    }
    public StagedRecord(SObject rec) {
        Map<String,Schema.DisplayType> fieldTypes = PWUtils.getFieldTypesForObject(rec.getSObjectType().getDescribe().getName());
        for (String field : fieldTypes.keySet()) {
            Schema.DisplayType fieldType = fieldTypes.get(field);
            if(fieldType == Schema.DisplayType.REFERENCE && field != 'CreatedById' && field != 'LastModifiedById') {
                try {
                    this.references.put(field, (String) rec.get(field));
                } catch (SObjectException e) {
                    if(e.getMessage().startsWith('SObject row was retrieved via SOQL without querying the requested field')) {
                        //do nothing
                    } else {
                        throw e;
                    }
                }
            }
        }
        this.initiate(rec);
    }
    public virtual void initiate(){
        this.initiate(null);
    }
    public void initiate(SObject rec) {
        // System.debug('INITIATING (Id/InternalId):' + this.Id + '/' + this.internalId);
        String existingId = this.Id;
        if(rec != null) {
            this.record = rec;
        }
        if(this.record.Id == null) {
            this.stagedFor = StagedAction.InsertAction;
            if(this.record != null) {
                this.internalId = this.hash(this.record);
            }
        } else {
            this.stagedFor = StagedAction.NoAction;
            this.internalId = null;
        }
        if(existingId != null && this.Id != existingId) {
            StagedDatabase.reMap(existingId, this.Id);
        }
    }
    public override Object get(String path) {
        if(this.idOverrides != null && this.idOverrides.containsKey(path)) {
            return this.idOverrides.get(path);
        }
        if(this.record == null) {
            return null;
        }
        if(path == 'Id') {
            return this.Id;
        }
        return PWUtils.getField(this.record, path);
    }
    public void set(String path, Object value) {
        if(path != 'Id' && this.get(path) == value) {
            return;
        }
        if(this.changes != null) {
            this.changes.put(path, this.get(path) + '');
        }
        if(path == 'Id') {
            if(this.stagedFor == StagedAction.InsertAction && PWUtils.isId((String) value)) {
                this.inserted((Id) value);
                return;
            }
            // System.debug('SETTING INTERNAL ID: ' + value);
            this.internalId = (String) value;
            if(value == null && this.record.Id != null) {
                this.record.Id = (String) value;
            }
            return;
        }
        if(this.record == null) {
            // This should only be the case when being deserialized
            return;
        }
        PWUtils.setField(this.record, path, value);
        this.touch();
    }
    public virtual void setLookup (String field, StagedRecord rec) {
        // this.lookups.put(field, rec);
        String recId;
        if(rec != null) {
            StagedDatabase.put(rec);
            recId = rec.Id;
        }
        String idField = PWUtils.getIdFieldForRef(field);
        this.setReference(idField, recId);
    }
    public void setReference (String field, String value) {
        this.setReference(field, value, false);
    }
    public void setReference (String field, String value, Boolean useOverride) {
        if(value == null && !useOverride) {
            this.idOverrides.remove(field);
            this.set(field, null);
            return;
        }
        if(PWUtils.isId(value)) {
            this.set(field, value);
        } else {
            if(field == 'ParentId') {
                StagedRecord rec = StagedDatabase.get(value);
                if(rec != null && rec.getType() != this.getType()) {
                    System.assert(false, 'ATTEMPT_TO_SET_INVALID_PARENT');
                }
            }
            this.idOverrides.put(field, value);
            this.touch();
        }
        this.references.put(field, value);
    }
    public virtual Boolean replaceReference(String oldId, String newId) {
        // System.debug('REPLACING REF: ' + oldId + ' -> ' + newId);
        if(oldId == null) {
            return false;
        }
        StagedAction action = this.stagedFor;
        if(this.idOverrides.values().contains(oldId)) {
            String recJson = this.toJSON();
            // System.debug('REPLACING REFERENCE: ' + oldId + ' -> ' + newId + '\n' + recJson);
            String[] keysToRemove = new String[]{};
            for(String key : this.idOverrides.keySet()) {
                if(this.idOverrides.get(key) == oldId) {
                    keysToRemove.add(key);
                    try {
                        this.set(key, newId);
                    } catch (PWUtils.FieldUpdateException e) {
                        // ignore
                    }
                }
            }
            // System.debug('REPLACED FOR KEYS:' + JSON.serialize(keysToRemove));
            for (String key : keysToRemove) {
                this.idOverrides.remove(key);
            }
            if(this.Id == oldId) {
                // Manually replace Id without triggering further adjustments to other records
                this.internalId = null;
                this.record.Id = newId;
                this.stagedFor = StagedAction.NoAction;
                this.inserted = true;
            }
            // System.debug('FINAL:' + JSON.serialize(this));
            return true;
        } else if (this.references.values().contains(oldId)) {
            String field;
            for (String lookupField : this.references.keySet()) {
                if(this.references.get(lookupField) == oldId) {
                    try {
                        this.set(lookupField, newId);
                    } catch (PWUtils.FieldUpdateException e) {
                        // do nothing
                    }
                    this.references.put(lookupField, newId);
                }
            }
            return true;
        }
        return false;
    }
    public StagedRecord getLookup (String ref) {
        return StagedDatabase.get((String) this.get(PWUtils.getIdFieldForRef(ref)));
    }
    public virtual SObject getRecord(){
        return this.record;
    }
    public static List<SObject> getRecords(List<StagedRecord> stagedRecords) {
        List<SObject> result = new List<SObject>();
        for (StagedRecord rec : stagedRecords) {
            result.add(rec.getRecord());
        }
        return result;
    }
    public void touch(){
        if(this.stagedFor == StagedAction.NoAction) {
            this.stagedFor = StagedAction.UpdateAction;
        }
    }
    public Boolean isInstanceOf(String typeName) {
        return this.getType() == typeName;
    }
    public String getType() {
        return this.record == null ? null : this.record.getSObjectType().getDescribe().getName();
    }
    private virtual String hash(SObject record) {
        // System.debug(JSON.serialize(record, true));
        // System.debug(Blob.valueOf(JSON.serialize(record, true)));
        // System.debug(Blob.valueOf(EncodingUtil.urlEncode(JSON.serialize(record, true), 'UTF-8')).toString());
        return EncodingUtil.base64Encode(Crypto.generateDigest('MD5',Blob.valueOf(JSON.serialize(record, true))));
    }
    private virtual String hash() {
        return this.hash(this.record);
    }
    public static StagedRecord copy(StagedRecord rec) {
        StagedRecord copied = (StagedRecord) JSON.deserialize(rec.toJSON(), StagedRecord.class);
        copied.Id = null;
        return copied;
    }
    private virtual List<Object> childArrayToJSON(String key){
        return new List<Object>();
    }
    protected virtual Object getOverrideField(String key) {
        return null;
    }
    protected virtual void resetExcludedProps() {
        this.excludedProperties = new String[] {
            'internalId',
            'sObjectType',
            'excludedProperties',
            'childArrayProperties'
            // 'Id'
        };
        this.childArrayProperties = new String[]{};
        this.overrideFields = new String[]{};
    }
    public virtual String toJSON() {
        return this.toJSON(false);
    }
    public virtual String toJSON(Boolean castToSObject) {
        this.resetExcludedProps();
        Map<String,Object> filtered = new Map<String,Object>();
        String rawJSON = JSON.serialize(this, true);
        Map<String,Object> entries = (Map<String,Object>) JSON.deserializeUntyped(rawJSON);
        for (String key : entries.keyset()) {
            if(!this.excludedProperties.contains(key)) {
                filtered.put(key, entries.get(key));
            }
        }
        for (String key : this.childArrayProperties) {
            List<Object> childArray = this.childArrayToJSON(key);
            if(castToSObject) {
                Map<String,List<Object>> queryResult = new Map<String,List<Object>>();
                queryResult.put('records', this.childArrayToJSON(key));
                filtered.put(key, queryResult);
            } else {
                filtered.put(key, childArray);
            }
        }
        if(castToSObject) {
            for (String key : this.overrideFields) {
                filtered.put(key, this.getOverrideField(key));
            }
        }
        return JSON.serialize(filtered);
    }
}