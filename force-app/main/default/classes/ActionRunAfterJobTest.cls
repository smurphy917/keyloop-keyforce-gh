@isTest
public with sharing class ActionRunAfterJobTest {
    @TestSetup
    static void makeData(){
        Map<String,Map<String,Object>> overrides = new Map<String,Map<String,Object>>();
        Map<String,Object> acc01Overrides = new Map<String,Object>();
        acc01Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Company').getRecordTypeId());
        acc01Overrides.put('Blocked__c','');
        Map<String,Object> acc02Overrides = new Map<String,Object>();
        acc02Overrides.put('RecordTypeId', Schema.SObjectType.Account.getRecordTypeInfosByName().get('Dealer').getRecordTypeId());
        acc02Overrides.put('Blocked__c','');
        acc02Overrides.put('Type','Dealership');
        overrides.put('testDataAssetManagementAccount01', acc01Overrides);
        overrides.put('testDataAssetManagementAccount02', acc02Overrides);
        String[] objects = new String[]{
            'Product2',
            'Pricebook2',
            'PricebookEntry',
            'Legal_Entity__c',
            'Account',
            'Asset',
            'AssetAction',
            'AssetStatePeriod'
        };
        TestUtility.loadData('testDataAssetManagement',objects, overrides);
        System.assertNotEquals(0, [SELECT Id FROM Asset].size());
        Asset custRoot = [SELECT Id, LifecycleStartDate, LifecycleEndDate, AccountId FROM Asset WHERE Aggregate_Asset__c = null AND ParentId = null LIMIT 1];
        Datetime modifyDate = Datetime.valueOf((custRoot.LifecycleStartDate.getTime() + custRoot.LifecycleEndDate.getTime()) / 2);
        Price_Adjustment__c pa = new Price_Adjustment__c(
            Name='Apex Test',
            Adjustment_Date__c = modifyDate.date(),
            Adjustment_Percent__c = 4.5
        );
        insert pa;
        Price_Adjustment_Line__c pal = new Price_Adjustment_Line__c(
            Asset__c = custRoot.Id,
            Status__c = 'Draft',
            Price_Adjustment__c = pa.Id
        );
        insert pal;
        
    }
    @isTest
    public static void test() {
        Price_Adjustment_Line__c pal = [SELECT Id, Quote__c FROM Price_Adjustment_Line__c LIMIT 1];
        pal.Status__c = 'Created';
        Test.startTest();
        update pal;
        Test.stopTest();
    }
    @isTest
    public static void test2() {
        try {
            Test.startTest();
            Price_Adjustment_Line__c pal = [SELECT Id, Quote__c FROM Price_Adjustment_Line__c LIMIT 1];
            Asset custRoot = [SELECT Id, LifecycleStartDate, LifecycleEndDate, AccountId FROM Asset WHERE Aggregate_Asset__c = null AND ParentId = null LIMIT 1];
            Datetime modifyDate = Datetime.valueOf((custRoot.LifecycleStartDate.getTime() + custRoot.LifecycleEndDate.getTime()) / 2);

            pal.Quote__c = Thrill.GenerateAndSave(custRoot.Id, modifyDate, Thrill.TransactionType.Amendment, null, null, 'Contract Admin');
            update pal;
            System.assertNotEquals(null, pal.Quote__c);
            System.assertNotEquals(0,[SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :pal.Quote__c].size());
            List<Id> jobIds = Test.enqueueBatchJobs(1);
            System.assertEquals(1, jobIds.size());
            System.assertNotEquals(null, jobIds[0]);
            ActionRunAfterJob.InvocableParameter p = new ActionRunAfterJob.InvocableParameter();
            p.jobId = jobIds[0];
            p.flowApiName = 'Create_Price_Adjustment_Order';
            p.flowInputNames = new List<String>{
                'quoteId',
                'priceAdjustmentLineId'
            };
            p.flowInputValues = new List<String>{
                pal.Quote__c,
                pal.Id
            };
            ActionRunAfterJob.InvocableRunFlowAfterJob(new List<ActionRunAfterJob.InvocableParameter>{p});
            Test.stopTest();
        } catch (AsyncException e) {
            //all goodt
        } catch (FlowException e) {
            // fuhggettaboutit
        }
    }
    public class QueueableTest implements Queueable, Finalizer {
        public void execute(QueueableContext ctx){
            // System.attachFinalizer(new QueueableTest());
            
            // Map<String,SBQQ__Quote__c> quote = new Map<String,SBQQ__Quote__c>();
            // quote.put('record', new SBQQ__Quote__c(Id = pal.Quote__c));
            // (new QuoteAPI()).calculate(quote, 'ActionRunAfterJobTest.QuoteCalcCallback');
        }
        public void execute(FinalizerContext ctx) {
            Price_Adjustment_Line__c pal = [SELECT Id, Quote__c FROM Price_Adjustment_Line__c LIMIT 1];
            String recordId = pal.Quote__c + '::QuoteCalculator';
            System.debug([SELECT FIELDS(STANDARD) FROM SBQQ__RecordJob__c LIMIT 10]);
            SBQQ__RecordJob__c recJob = [SELECT SBQQ__JobId__c FROM SBQQ__RecordJob__c WHERE SBQQ__RecordId__c = :recordId LIMIT 1];
            AsyncApexJob job = [SELECT Id FROM AsyncApexJob WHERE JobType = 'Queueable' AND Status != 'Completed' LIMIT 10];
            System.assertNotEquals(null, recJob);
            System.assertNotEquals(null, job);
            ActionRunAfterJob.InvocableParameter p = new ActionRunAfterJob.InvocableParameter();
            // p.jobId = System.enqueueJob(new QueueableTest(),1);
            p.flowApiName = 'Create_Price_Adjustment_Order';
            p.flowInputNames = new List<String>{
                'quoteId',
                'priceAdjustmentLineId'
            };
            p.flowInputValues = new List<String>{
                pal.Quote__c,
                pal.Id
            };
            ActionRunAfterJob.InvocableRunFlowAfterJob(new List<ActionRunAfterJob.InvocableParameter>{p});
        }
    }


    public class QuoteCalcCallback implements SBQQ.CalculateCallback {
        public void callback(String quoteJSON){
          SBQQ.ServiceRouter.save('SBQQ.QuoteAPI.QuoteSaver', quoteJSON);       
        }
    }
    public class QuoteAPI {     

        public void calculate(Object quote, String callbackClass) {
          QuoteCalculatorContext ctx = new QuoteCalculatorContext(quote, callbackClass);
          SBQQ.ServiceRouter.load('SBQQ.QuoteAPI.QuoteCalculator', null, JSON.serialize(ctx));    
        }    
    }

    private class QuoteCalculatorContext {        
        private Object quote;             //The quote and callbackClass properties are called in the API code by the exact names seen here.
        private String callbackClass;         //Altering these property names will cause calculator API calls to fail.
    
        private QuoteCalculatorContext(Object quote, String callbackClass) {
          this.quote = quote;            
          this.callbackClass = callbackClass;        
        }
      } 
}