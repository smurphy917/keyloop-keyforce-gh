@isTest
public with sharing class TimePeriodTest {

    @isTest
    public static void test() {
        Datetime anchor = Datetime.now();
        Datetime d1 = anchor;
        Datetime d2 = anchor.addMonths(1);
        Datetime d3 = anchor.addYears(1);
        Datetime d4 = anchor.addYears(1).addMonths(6);
        System.debug(JSON.serialize(new Datetime[]{d1,d2,d3,d4}));
        Map<String,Double> v1 = new Map<String,Double>();
        v1.put('a', 100);
        v1.put('b', 200);
        TimePeriod tp1 = new TimePeriod(d1, d3, new List<String>(), v1);
        Map<String,Double> v2 = new Map<String,Double>();
        v2.put('b', 200);
        v2.put('c', 400);
        TimePeriod tp2 = new TimePeriod(d2, d4, new List<String>(), v2);

        List<Periodic> normed = TimePeriod.normalize(new List<TimePeriod>{tp1,tp2});
        System.debug(JSON.serialize(normed));
        System.assertEquals(3,normed.size());
        // Left-most
        System.assertEquals(d1, normed[0].getStart(), 'Left-most start date unexpected');
        System.assertEquals(d2.addSeconds(-1), normed[0].getEnd(),'Left-most end date unexpected');
        System.assertEquals(100,normed[0].getValues().get('a'), 'Left-most value unexpected: a');
        System.assertEquals(200,normed[0].getValues().get('b'), 'Left-most value unexpected: b');
        System.assertEquals(null,normed[0].getValues().get('c'), 'Left-most value unexpected: c');

        // Mid
        System.assertEquals(d2, normed[1].getStart(), 'Mid start date unexpeced');
        System.assertEquals(d3.addSeconds(-1), normed[1].getEnd(), 'Mid end date unexpected');
        System.assertEquals(100, normed[1].getValues().get('a'), 'Mid value unexpected: a');
        System.assertEquals(400, normed[1].getValues().get('b'), 'Mid value unexpected: b');
        System.assertEquals(400, normed[1].getValues().get('c'), 'Mid value unexpected: c');

        // Right
        System.assertEquals(d3, normed[2].getStart(), 'Right-most start date unexpected');
        // System.assertEquals(d4, normed[2].getEnd(),'Right-most end date unexpected');
        System.assertEquals(null,normed[2].getValues().get('a'), 'Right-most value unexpected: a');
        System.assertEquals(200,normed[2].getValues().get('b'), 'Right-most value unexpected: b');
        System.assertEquals(400,normed[2].getValues().get('c'), 'Right-most value unexpected: c');
    }

    @isTest
    public static void test2() {
        Datetime anchor = Datetime.now();
        Datetime d1 = anchor;
        Datetime d2 = anchor.addMonths(1);
        Datetime d3 = anchor.addYears(1);
        Datetime d4 = anchor.addYears(1).addMonths(6);

        System.debug(JSON.serialize(new Datetime[]{d1,d2,d3,d4}));
        Map<String,Double> v1 = new Map<String,Double>();
        v1.put('oneTimeAmount', 100);
        v1.put('Mrr', 200);
        TimePeriod tp1 = new TimePeriod(d1, d2, new List<String>(), v1);
        Map<String,Double> v2 = new Map<String,Double>();
        v2.put('oneTimeAmount', 200);
        v2.put('Mrr', 400);
        TimePeriod tp2 = new TimePeriod(d3, d4, new List<String>(), v2);
        System.debug(JSON.serialize(TimePeriod.normalize(new List<TimePeriod>{tp1,tp2},null,null,StagedAssetStatePeriod.class)));
    }
}