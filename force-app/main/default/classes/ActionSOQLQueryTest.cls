@isTest
public with sharing class ActionSOQLQueryTest {

    @TestSetup
    static void makeData(){
        Account a = new Account(Name='Apex Test Account');
        insert a;
    }

    @isTest
    static void runAggregate() {
        ActionSOQLQuery.InvocableParameter param = new ActionSOQLQuery.InvocableParameter();
        param.query = 'SELECT Name result FROM Account GROUP BY Name LIMIT 10';
        param.resultKey = 'result';
        List<String> baseVals = new List<String>();
        List<AggregateResult> baseResults = Database.query(param.query);
        for (AggregateResult baseResult : baseResults) {
            baseVals.add((String) baseResult.get('result'));
        }

        List<ActionSOQLQuery.Result> results = ActionSOQLQuery.InvocableSOQLQuery(new ActionSOQLQuery.InvocableParameter[]{param});
        for (ActionSOQLQuery.Result result : results) {
            System.assertEquals(baseVals.size(), result.records.size());
            for (String val : result.records) {
                System.assert(baseVals.contains(val));
            }
        }
    }
    @isTest
    static void run() {
        ActionSOQLQuery.InvocableParameter param = new ActionSOQLQuery.InvocableParameter();
        param.query = 'SELECT Name FROM Account LIMIT 10';
        param.sobjectType = 'Account';
        List<Account> baseResults = (List<Account>) Database.query(param.query);

        List<ActionSOQLQuery.Result> results = ActionSOQLQuery.InvocableSOQLQuery(new ActionSOQLQuery.InvocableParameter[]{param});
        for (ActionSOQLQuery.Result result : results) {
            System.assertEquals(baseResults.size(), result.sobjectRecords.size());
            for (Account val : (List<Account>) result.sobjectRecords) {
                Boolean match = false;
                for (Account a : baseResults) {
                    match = a.Id == val.Id;
                    if(match){
                        break;
                    }
                }
                System.assert(match);
            }
        }
    }
    @isTest
    static void runUncast() {
        ActionSOQLQuery.InvocableParameter param = new ActionSOQLQuery.InvocableParameter();
        param.query = 'SELECT Name FROM Account LIMIT 10';
        List<Account> baseResults = (List<Account>) Database.query(param.query);

        List<ActionSOQLQuery.Result> results = ActionSOQLQuery.InvocableSOQLQuery(new ActionSOQLQuery.InvocableParameter[]{param});
        for (ActionSOQLQuery.Result result : results) {
            System.assertEquals(baseResults.size(), result.sobjectRecords.size());
            for (Account val : (List<Account>) result.sobjectRecords) {
                Boolean match = false;
                for (Account a : baseResults) {
                    match = a.Id == val.Id;
                    if(match){
                        break;
                    }
                }
                System.assert(match);
            }
        }
    }
}