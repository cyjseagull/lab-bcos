/*
 * @CopyRight:
 * FISCO-BCOS is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FISCO-BCOS is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with FISCO-BCOS.  If not, see <http://www.gnu.org/licenses/>
 * (c) 2016-2018 fisco-dev contributors.
 */

/**
 * @brief: fake interface
 *         fake Block
 *         fake BlockChainInterface
 *         fake BlockVerifierInterface
 *         fake Ledger
 * @file: Fake.h
 * @author: chaychen
 * @date: 2018-10-08
 */

#pragma once
#include <libblockchain/BlockChainInterface.h>
#include <libblockverifier/BlockVerifierInterface.h>
#include <libdevcrypto/Common.h>
#include <libethcore/Block.h>
#include <libethcore/CommonJS.h>
#include <libethcore/Transaction.h>
#include <libethcore/TransactionReceipt.h>
#include <libledger/Ledger.h>
#include <libledger/LedgerParam.h>
#include <libsync/SyncInterface.h>
#include <libsync/SyncStatus.h>
#include <unistd.h>
#include <ctime>
class FakeBlockChain : public dev::blockchain::BlockChainInterface
{
public:
    FakeBlockChain()
    {
        m_blockNumber = 1;
        m_totalTransactionCount = 0;
        dev::bytes m_blockHeaderData = dev::bytes();
        dev::bytes m_blockData = dev::bytes();
        dev::eth::BlockHeader blockHeader;
        blockHeader.setSealer(dev::u256(1));
        blockHeader.setNumber(0);
        blockHeader.setTimestamp(0);
        dev::eth::Block block;
        block.setBlockHeader(blockHeader);
        block.encode(m_blockData);
        m_blockHash[block.blockHeaderHash()] = 0;
        m_blockChain.push_back(std::make_shared<Block>(block));
    }

    ~FakeBlockChain() {}

    int64_t number()
    {
        dev::ReadGuard l(x_blockChain);
        return m_blockChain.size() - 1;
    }

    std::pair<int64_t, int64_t> totalTransactionCount()
    {
        dev::ReadGuard l(x_blockChain);
        return std::make_pair(m_totalTransactionCount, m_blockChain.size() - 1);
    }

    dev::h256 numberHash(int64_t _i)
    {
        dev::ReadGuard l(x_blockChain);
        return m_blockChain[_i]->headerHash();
    }

    std::shared_ptr<dev::eth::Block> getBlockByHash(dev::h256 const& _blockHash) override
    {
        dev::ReadGuard l(x_blockChain);
        if (m_blockHash.count(_blockHash))
            return m_blockChain[m_blockHash[_blockHash]];
        return nullptr;
    }
    dev::eth::LocalisedTransaction getLocalisedTxByHash(dev::h256 const& _txHash) override
    {
        return LocalisedTransaction();
    }
    dev::eth::Transaction getTxByHash(dev::h256 const& _txHash) override
    {
        return dev::eth::Transaction();
    }
    dev::eth::TransactionReceipt getTransactionReceiptByHash(dev::h256 const& _txHash) override
    {
        return dev::eth::TransactionReceipt();
    }

    dev::eth::LocalisedTransactionReceipt getLocalisedTxReceiptByHash(
        dev::h256 const& _txHash) override
    {
        return dev::eth::LocalisedTransactionReceipt(dev::eth::TransactionReceipt(), dev::h256(0),
            dev::h256(0), -1, dev::Address(), dev::Address(), -1, 0);
    }

    std::shared_ptr<dev::eth::Block> getBlockByNumber(int64_t _i) override
    {
        return getBlockByHash(numberHash(_i));
    }

    CommitResult commitBlock(
        dev::eth::Block& block, std::shared_ptr<dev::blockverifier::ExecutiveContext>) override
    {
        if (block.blockHeader().number() == number() + 1)
        {
            dev::WriteGuard l(x_blockChain);
            {
                m_blockHash[block.blockHeader().hash()] = block.blockHeader().number();
                m_blockChain.push_back(std::make_shared<Block>(block));
                m_blockNumber = block.blockHeader().number() + 1;
                m_totalTransactionCount += block.transactions().size();
            }
            m_onReady();
        }
        return CommitResult::OK;
    }

    void setGroupMark(std::string const& groupMark) override {}

    dev::bytes getCode(dev::Address _address) override { return dev::bytes(); }

private:
    std::map<dev::h256, uint64_t> m_blockHash;
    std::vector<std::shared_ptr<Block>> m_blockChain;
    uint64_t m_blockNumber;
    uint64_t m_totalTransactionCount;
    mutable dev::SharedMutex x_blockChain;
};

class FakeBlockSync : public dev::sync::SyncInterface
{
public:
    FakeBlockSync() { m_status.state = dev::sync::SyncState::Idle; };
    virtual ~FakeBlockSync(){};
    /// start blockSync
    void start(){};
    /// stop blockSync
    void stop(){};

    /// get status of block sync
    /// @returns Synchonization status
    dev::sync::SyncStatus status() const override { return m_status; };
    bool isSyncing() const override { return false; };

    /// protocol id used when register handler to p2p module
    dev::PROTOCOL_ID const& protocolId() const override { return m_protocolID; };
    void setProtocolId(dev::PROTOCOL_ID const _protocolId) override{};

private:
    dev::sync::SyncStatus m_status;
    dev::PROTOCOL_ID m_protocolID = 0;
};

class FakeBlockVerifier : public dev::blockverifier::BlockVerifierInterface
{
public:
    FakeBlockVerifier()
    {
        m_executiveContext = std::make_shared<dev::blockverifier::ExecutiveContext>();
        std::srand(std::time(nullptr));
    };
    virtual ~FakeBlockVerifier(){};
    std::shared_ptr<dev::blockverifier::ExecutiveContext> executeBlock(
        dev::eth::Block& block, dev::blockverifier::BlockInfo const& parentBlockInfo) override
    {
        /// execute time: 1000
        /// usleep(1000 * (block.getTransactionSize()));
        fakeExecuteResult(block);
        return m_executiveContext;
    };
    /// fake the transaction receipt of the whole block
    void fakeExecuteResult(dev::eth::Block& block)
    {
        dev::eth::TransactionReceipts receipts;
        for (unsigned index = 0; index < block.getTransactionSize(); index++)
        {
            dev::eth::TransactionReceipt receipt(dev::u256(0), dev::u256(100),
                dev::eth::LogEntries(), dev::u256(0), dev::bytes(),
                block.transactions()[index].receiveAddress());
            receipts.push_back(receipt);
        }
        block.setTransactionReceipts(receipts);
    }

    virtual std::pair<dev::executive::ExecutionResult, dev::eth::TransactionReceipt>
    executeTransaction(const dev::eth::BlockHeader& blockHeader, dev::eth::Transaction const& _t)
    {
        dev::executive::ExecutionResult res;
        dev::eth::TransactionReceipt reciept;
        return std::make_pair(res, reciept);
    }

private:
    std::shared_ptr<dev::blockverifier::ExecutiveContext> m_executiveContext;
};

class FakeLedger : public dev::ledger::Ledger
{
public:
    FakeLedger(std::shared_ptr<dev::p2p::P2PInterface> service, dev::GROUP_ID const& _groupId,
        dev::KeyPair const& _keyPair, std::string const& _baseDir, std::string const& _configFile)
      : Ledger(service, _groupId, _keyPair, _baseDir, _configFile)
    {}
    /// init the ledger(called by initializer)
    bool initLedger() override
    {
        /// init dbInitializer
        m_dbInitializer = std::make_shared<dev::ledger::DBInitializer>(m_param);
        /// init blockChain
        initBlockChain();
        /// intit blockVerifier
        initBlockVerifier();
        /// init txPool
        initTxPool();
        /// init sync
        Ledger::initSync();
        /// init consensus
        Ledger::consensusInitFactory();
        return true;
    }

    /// init blockverifier related
    bool initBlockVerifier() override
    {
        m_blockVerifier = std::make_shared<FakeBlockVerifier>();
        return true;
    }
    bool initBlockChain() override
    {
        m_blockChain = std::make_shared<FakeBlockChain>();
        return true;
    }
};
