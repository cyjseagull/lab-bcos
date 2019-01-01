/*
    This file is part of FISCO-BCOS.

    FISCO-BCOS is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    FISCO-BCOS is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with FISCO-BCOS.  If not, see <http://www.gnu.org/licenses/>.
*/
/** @file Initializer.h
 *  @author chaychen
 *  @modify first draft
 *  @date 20181022
 */

#pragma once

#include "Common.h"
#include "InitializerInterface.h"
#include "LedgerInitializer.h"
#ifndef FISCO_EASYLOG
#include "BoostLogInitializer.h"
#else
#include "EasyLogInitializer.h"
#endif
#include "P2PInitializer.h"
#include "RPCInitializer.h"
#include "SecureInitializer.h"

namespace dev
{
namespace initializer
{
class Initializer : public InitializerInterface, public std::enable_shared_from_this<Initializer>
{
public:
    typedef std::shared_ptr<Initializer> Ptr;

    void init(std::string const& _path);

    SecureInitializer::Ptr secureInitializer() { return m_secureInitializer; }
    P2PInitializer::Ptr p2pInitializer() { return m_p2pInitializer; }
    LedgerInitializer::Ptr ledgerInitializer() { return m_ledgerInitializer; }
    RPCInitializer::Ptr rpcInitializer() { return m_rpcInitializer; }
    LogInitializer::Ptr logInitializer() { return m_logInitializer; }

private:
    LedgerInitializer::Ptr m_ledgerInitializer;
    P2PInitializer::Ptr m_p2pInitializer;
    RPCInitializer::Ptr m_rpcInitializer;

    LogInitializer::Ptr m_logInitializer;
    SecureInitializer::Ptr m_secureInitializer;
};

}  // namespace initializer

}  // namespace dev
