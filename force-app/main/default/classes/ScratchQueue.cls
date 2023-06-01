public with sharing class ScratchQueue implements Queueable{
    List<Id> ids;
    public ScratchQueue(List<Id> ids) {
        this.ids = ids;
    }
    public void execute (QueueableContext ctx) {
        Id id = ids[0];
        List<Id> remaining = new List<Id>();
        for (Object remId : PWUtils.slice(this.ids, 0)) {
            remaining.add((Id) remId);
        }
        this.ids = remaining;
        Serenity.CancelAll(id);
    }
    public void finish(QueueableContext ctx) {
        if(this.ids.size() > 0) {
            System.enqueueJob(new ScratchQueue(this.ids));
        }
    }
}