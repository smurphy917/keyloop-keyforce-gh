public class ActionSOQLQuery {
    @TestVisible
    public class InvocableParameter {
        @InvocableVariable(label='SOQL to Execute' description='Values for the column aliased as \'result\' will be returned' required=true)
        public String query;
        @InvocableVariable(label='Aggregate result key')
        public String resultKey;
        @InvocableVariable(label='Cast to SObject Type')
        public String sobjectType;
    }
    public class Result {
        @InvocableVariable(label='Results')
        public List<String> records;
        @InvocableVariable(label='Records')
        public List<SObject> sobjectRecords;
    }

    @InvocableMethod(label='Execute SOQL Query')
    public static List<Result> InvocableSOQLQuery(List<InvocableParameter> parameters) {
        List<Result> resultList = new List<Result>();
        for (InvocableParameter p : parameters) {
            Result result = new Result();
            if(p.resultKey != null) {
                result.records = new List<String>();
                List<AggregateResult> qResult = Database.query(p.query);
                for (AggregateResult res : qResult) {
                    result.records.add((String) res.get(p.resultKey));
                }
            } else {
                List<SObject> recs = Database.query(p.query);
                if(p.sobjectType != null) {
                    List<SObject> castRecords = new List<SObject>();
                    for (SObject rec : recs) {
                        Map<String,Object> fields = rec.getPopulatedFieldsAsMap();
                        SObject record = (SObject) Type.forName(p.sobjectType).newInstance();
                        for (String fieldName : fields.keySet()) {
                            record.put(fieldName, fields.get(fieldName));
                        }
                        castRecords.add(record);
                    }
                    result.sobjectRecords = castRecords;
                } else {
                    result.sobjectRecords = recs;
                }
            }
            resultList.add(result);
        }
        return resultList;
    }
}