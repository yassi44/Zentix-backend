import { ethers, network } from "hardhat";
import { verify } from "../utils/verify";

async function main() {
    const isLocalhost = network.name.includes("localhost") || network.name.includes("hardhat");
    
    let USDC_ADDRESS: string;
    let AAVE_POOL_ADDRESS: string;
    
    if (isLocalhost) {
        console.log("🔧 Déploiement des mocks pour le réseau local...");
        
        // Deploy MockERC20 (USDC)
        const MockERC20 = await ethers.deployContract("MockERC20", [
            "USD Coin",
            "USDC", 
            6
        ]);
        await MockERC20.waitForDeployment();
        console.log(`📄 MockUSDC déployé à : ${MockERC20.target}`);

        // Deploy MockAavePool
        const MockAavePool = await ethers.deployContract("MockAavePool");
        await MockAavePool.waitForDeployment();
        console.log(`🏦 MockAavePool déployé à : ${MockAavePool.target}`);

        // Setup aToken address in MockAavePool
        await MockAavePool.setATokenAddress(MockERC20.target, MockERC20.target);
        console.log("aToken address configurée");

        USDC_ADDRESS = MockERC20.target.toString();
        AAVE_POOL_ADDRESS = MockAavePool.target.toString();
    } else {
        // Adresses pour Sepolia
        USDC_ADDRESS = "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8";
        AAVE_POOL_ADDRESS = "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951";
    }
    
    const constructorArgs = [USDC_ADDRESS, AAVE_POOL_ADDRESS];
    
    console.log("🚀 Déploiement de ZentixVault...");
    console.log(`   USDC: ${USDC_ADDRESS}`);
    console.log(`   Aave Pool: ${AAVE_POOL_ADDRESS}`);
    
    const ZentixVault = await ethers.deployContract("ZentixVault", constructorArgs);
    
    await ZentixVault.waitForDeployment();
    
    if (!isLocalhost) {
        console.log("⏳ Attente de 5 blocs avant la vérification...");
        await ZentixVault.deploymentTransaction()?.wait(5);
    }
    
    console.log(` ZentixVault déployé à : ${ZentixVault.target}`);
    
    if (!isLocalhost) {
        console.log("🔍 Vérification du contrat sur Etherscan...");
        await verify(ZentixVault.target.toString(), constructorArgs);
    }
    
    console.log("\n Résumé du déploiement:");
    console.log(`   Réseau: ${network.name}`);
    console.log(`   ZentixVault: ${ZentixVault.target}`);
    console.log(`   USDC: ${USDC_ADDRESS}`);
    console.log(`   Aave Pool: ${AAVE_POOL_ADDRESS}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});