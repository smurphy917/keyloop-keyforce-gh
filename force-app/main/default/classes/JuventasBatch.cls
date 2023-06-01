public with sharing class JuventasBatch implements Database.Batchable<Juventas.DataBlock> {
    public List<Juventas.DataBlock> blocks;
    public Juventas.BatchConfig config;
    public JuventasBatch(List<Juventas.DataBlock> blocks) {
        this.blocks = blocks;
        this.config = Juventas.config;
    }
    public Iterable<Juventas.DataBlock> start(Database.BatchableContext ctx) {
        return this.blocks;
    }
    public void execute(Database.BatchableContext ctx, List<Juventas.DataBlock> blocks) {
        Juventas.config = this.config;
        for (Juventas.DataBlock block : blocks) {
            Juventas.immortaliseBlock(block);
        }
    }
    public void finish(Database.BatchableContext ctx) {}
}