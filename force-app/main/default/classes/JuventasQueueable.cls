public with sharing class JuventasQueueable implements Queueable {
    List<Juventas.DataBlock> blocks;
    Juventas.BatchConfig config;
    public JuventasQueueable(List<Juventas.DataBlock> blocks, Juventas.BatchConfig config) {
        this.blocks = blocks;
        this.config = config;
    }
    public void execute(QueueableContext ctx) {
        Juventas.config = this.config;
        List<List<Juventas.DataBlock>> batchedBlocks = new List<List<Juventas.DataBlock>>();
        for (Integer idx = 0; idx < Juventas.config.concurrentBatches; idx++) {
            batchedBlocks.add(new List<Juventas.DataBlock>());
        }
        List<Juventas.DataBlock> workingBlocks = new List<Juventas.DataBlock>();
        Integer batchCount = 0;
        Id workingCustomerId = this.blocks[0].customerId;
        for (Juventas.DataBlock block : this.blocks) {
            if(block.customerId != workingCustomerId) {
                batchedBlocks.get(Integer.valueOf(PWUtils.mod(batchCount, this.config.concurrentBatches))).addAll(workingBlocks);
                workingBlocks = new List<Juventas.DataBlock>();
                batchCount++;
            }
            workingBlocks.add(block);
            workingCustomerId = block.customerId;
        }
        batchedBlocks.get(Integer.valueOf(PWUtils.mod(batchCount, this.config.concurrentBatches))).addAll(workingBlocks);
        for (Integer idx = 0; idx < this.config.concurrentBatches; idx++) {
            List<Juventas.DataBlock> batch = batchedBlocks.get(idx);
            if(batch.size() > 0) {
                Integer batchSize = Juventas.config.blockBatchSize;
                if(Test.isRunningTest()) {
                    batchSize = batch.size();
                }
                Database.executeBatch(new JuventasBatch(batch), batchSize);
            }
        }
    }
}