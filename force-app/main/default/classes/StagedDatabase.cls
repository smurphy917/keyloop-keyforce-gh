public with sharing class StagedDatabase {

    private static Map<String,StagedRecord> data = new Map<String,StagedRecord>();
    private static Map<String,String> idHash = new Map<String,String>();

    public static List<StagedRecord> addWhere(String objName, String soqlWhere, List<String> expandFields, Type type) {
        return addAll(
            PWUtils.selectStar(objName, soqlWhere, expandFields),
            type
        );
    }
    public static List<StagedRecord> addWhere(String objName, String soqlWhere, List<String> expandFields) {
        return addAll(
            PWUtils.selectStar(objName, soqlWhere, expandFields)
        );
    }
    public static void put(StagedRecord record) {
        data.put(record.Id, record);
        // System.debug('SDB PUT: ' + record.Id);
    }
    public static void put(SObject record) {
        StagedRecord rec = new StagedRecord(record);
        data.put(rec.Id, rec);
        // System.debug('SDB PUT: ' + record.Id);
    }

    public static void reMap(String prevId, String newId) {
        if(data.containsKey(prevId)) {
            data.put(newId, data.get(prevId));
            data.remove(prevId);
        }
    }

    public static StagedRecord get(String id){
        if(id == null) {
            return null;
        }
        if(idHash.containsKey(id)){
            id = idHash.get(id);
        }
        if(data.containsKey(id)) {
            return data.get(id);
        }
        for (StagedRecord record : data.values()) {
            if(record.Id == id) {
                return record;
            }
        }
        return null;
    }
    public static List<StagedRecord> get(Set<String> recordIds) {
        return get(new List<String>(recordIds));
    }
    public static List<StagedRecord> get(List<String> recordIds) {
        List<StagedRecord> records = new List<StagedRecord>();
        for (String recId : recordIds) {
            records.add(get(recId));
        }
        return records;
    }
    public static StagedRecord add(Id recordId) { 
        return add(recordId, null, null);
    }
    public static StagedRecord add(Id recordId, String[] expandFields) { 
        return add(recordId, expandFields, null);
    }
    public static StagedRecord add(Id recordId, String[] expandFields, Type type) {
        addWhere(recordId.getSobjectType().getDescribe().getName(), 'Id=\'' + recordId+'\'', expandFields, type);
        return get(recordId);
    }
    public static List<StagedRecord> addAll(List<SObject> records) {
        List<StagedRecord> stagedRecs = new List<StagedRecord>();
        for(SObject record : records) {
            // System.debug('RAW RECORD:'); System.debug(record);
            StagedRecord rec = new StagedRecord(record);
            // System.debug('STAGED RECORD ID:'); System.debug(rec.Id);
            // System.debug('STAGED RECORD:'); System.debug(JSON.serialize(rec));
            data.put(rec.Id, rec);
            stagedRecs.add(rec);
        }
        return stagedRecs;
    }
    public static List<StagedRecord> addAll(List<StagedRecord> records) {
        for (StagedRecord record : records) {
            data.put(record.Id, record);
        }
        return records;
    }
    public static List<StagedRecord> addAll(List<SObject> records, Type type) {
        List<StagedRecord> stagedRecs = new List<StagedRecord>();
        for(SObject record : records) {
            StagedRecord rec;
            if(type != null) {
                rec = (StagedRecord) type.newInstance();
                rec.initiate(record);
            } else {
                rec = new StagedRecord(record);
            }
            data.put(rec.Id, rec);
            stagedRecs.add(rec);
        }
        return stagedRecs;
    }
    public static List<StagedRecord> query(QueryFunction fn){
        List<StagedRecord> results = new List<StagedRecord>();
        for(StagedRecord rec : data.values()) {
            if(fn.match(rec)) {
                results.add(rec);
            }
        }
        return results;
    }
    public static StagedRecord findOne(QueryFunction fn) {
        for (StagedRecord rec : data.values()) {
            if(fn.match(rec)) {
                return rec;
            }
        }
        return null;
    }
    

    public static List<StagedRecord> all() {
        return data.values();
    }

    public static List<String> rePoint(String prevId, String newId) {
        List<String> repointedIds = new List<String>();
        if(prevId == null) {
            return null;
        }
        for(StagedRecord rec : data.values()) {
            if(rec.replaceReference(prevId, newId)) {
                put(rec);
                repointedIds.add(rec.Id);
            }
        }
        return repointedIds;
    }

    public static void inserted(String prevId, StagedRecord record) {
        data.put(record.Id, record);
        // System.debug('StagedDatabase.inserted record:'+JSON.serialize(data.get(record.Id)));
        data.remove(prevId);
        idHash.put(prevId, record.Id);
        rePoint(prevId, record.Id);
    }

    public static String toJSON() {
        List<String> entries = new List<String>();
        for(StagedRecord record : data.values()) {
            entries.add(record.toJSON());
        }
        return '[' + String.join(entries, ',') + ']';
    }

    public interface QueryFunction {
        Boolean match(StagedRecord record);
    }

    public static State getState() {
        return new State();
    }

    public static void restore(State state) {
        data = state.data;
        idHash = state.idHash;
    }

    public class State {
        private Map<String,StagedRecord> data;
        private Map<String,String> idHash;

        public State() {
            this.data = StagedDatabase.data;
            this.idHash = StagedDatabase.idHash;
        }

    }
}