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
 * @brief : implementation of Ledger manager
 * @file: LedgerManager.h
 * @author: yujiechen
 * @date: 2018-10-23
 */
#pragma once
#include "Ledger.h"
#include "LedgerInterface.h"
#include <libethcore/Common.h>
#include <map>
namespace dev
{
namespace ledger
{
class LedgerManager
{
public:
    virtual bool initSingleLedger(std::shared_ptr<dev::p2p::P2PInterface> service,
        dev::eth::GroupID const& _groupId, dev::KeyPair const& _keyPair,
        std::string const& _baseDir);

    /// get pointer of txPool by group id
    inline std::shared_ptr<dev::txpool::TxPoolInterface> txPool(dev::eth::GroupID groupId)
    {
        if (!m_ledgerMap.count(groupId))
            return nullptr;
        return m_ledgerMap[groupId]->txPool();
    }
    /// get pointer of blockverifier by group id
    inline std::shared_ptr<dev::blockverifier::BlockVerifierInterface> blockVerifier(
        dev::eth::GroupID groupId)
    {
        if (!m_ledgerMap.count(groupId))
            return nullptr;
        return m_ledgerMap[groupId]->blockVerifier();
    }
    /// get pointer of blockchain by group id
    inline std::shared_ptr<dev::blockchain::BlockChainInterface> blockChain(
        dev::eth::GroupID groupId)
    {
        if (!m_ledgerMap.count(groupId))
            return nullptr;
        return m_ledgerMap[groupId]->blockChain();
    }
    /// get pointer of consensus by group id
    inline std::shared_ptr<dev::consensus::ConsensusInterface> consensus(dev::eth::GroupID groupId)
    {
        if (!m_ledgerMap.count(groupId))
            return nullptr;
        return m_ledgerMap[groupId]->consensus();
    }
    /// get pointer of blocksync by group id
    inline std::shared_ptr<dev::sync::SyncInterface> sync(dev::eth::GroupID groupId)
    {
        if (!m_ledgerMap.count(groupId))
            return nullptr;
        return m_ledgerMap[groupId]->sync();
    }

private:
    std::map<dev::eth::GroupID, std::shared_ptr<LedgerInterface>> m_ledgerMap;
};
}  // namespace ledger
}  // namespace dev