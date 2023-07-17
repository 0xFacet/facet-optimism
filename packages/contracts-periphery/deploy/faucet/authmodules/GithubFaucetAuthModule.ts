/* Imports: External */
import { DeployFunction } from 'hardhat-deploy/dist/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import '@nomiclabs/hardhat-ethers'
import '@eth-optimism/hardhat-deploy-config'
import 'hardhat-deploy'
import { BigNumber } from 'ethers'

import type { DeployConfig } from '../../../src'

const deployFn: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const deployConfig = hre.deployConfig as DeployConfig

  const { deployer } = await hre.getNamedAccounts()

  console.log('Deploying Github Auth Module')
  const { deploy } = await hre.deployments.deterministic(
    'GithubAdminFaucetAuthModule',
    {
      contract: 'AdminFaucetAuthModule',
      salt: hre.ethers.utils.solidityKeccak256(
        ['string'],
        ['AdminFaucetAuthModule']
      ),
      from: deployer,
      args: [
        deployConfig.githubFamAdmin,
        deployConfig.githubFamName,
        deployConfig.githubFamVersion,
      ],
      log: true,
      gasPrice: BigNumber.from(2000000000),
    }
  )

  await deploy()
}

deployFn.tags = ['Faucet', 'FaucetEnvironment']

export default deployFn
