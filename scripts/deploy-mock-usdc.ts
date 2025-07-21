import { ethers, network } from "hardhat";
import { verify } from "../utils/verify";
import { writeFileSync, readFileSync } from 'fs';
import { join } from 'path';

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("🚀 Déploiement avec le compte:", deployer.address);
    console.log("💰 Solde:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH");
    
    const isLocalhost = network.name.includes("localhost") || network.name.includes("hardhat");
    
    let USDC_ADDRESS: string;
    let AAVE_POOL_ADDRESS: string;
    const deployedContracts: Record<string, string> = {};
    
    if (isLocalhost) {
        console.log("\n🔧 Déploiement des mocks pour le réseau local...");
        
        // 1. Deploy MockERC20 (USDC)
        console.log("📄 Déploiement MockUSDC...");
        const mockUSDC = await ethers.deployContract("MockERC20", [
            "USD Coin",
            "USDC", 
            6
        ]);
        await mockUSDC.waitForDeployment();
        USDC_ADDRESS = mockUSDC.target.toString();
        deployedContracts.MockUSDC = USDC_ADDRESS;
        console.log(`✅ MockUSDC déployé à: ${USDC_ADDRESS}`);

        // 2. Deploy MockAavePool
        console.log("🏦 Déploiement MockAavePool...");
        const mockAavePool = await ethers.deployContract("MockAavePool");
        await mockAavePool.waitForDeployment();
        AAVE_POOL_ADDRESS = mockAavePool.target.toString();
        deployedContracts.MockAavePool = AAVE_POOL_ADDRESS;
        console.log(`✅ MockAavePool déployé à: ${AAVE_POOL_ADDRESS}`);

        // 3. Configure aToken address AVANT de déployer ZentixVault
        console.log("⚙️ Configuration du aToken...");
        const tx = await mockAavePool.setATokenAddress(USDC_ADDRESS, USDC_ADDRESS);
        await tx.wait();
        console.log("✅ aToken configuré (USDC = aUSDC pour simplifier)");
        
        // 3.1 Vérification de la configuration
        console.log("🔍 Vérification de la configuration aToken...");
        const reserveData = await mockAavePool.getReserveData(USDC_ADDRESS);
        console.log(`📋 aToken configuré dans reserve: ${reserveData.aTokenAddress}`);
        
        if (reserveData.aTokenAddress === "0x0000000000000000000000000000000000000000") {
            throw new Error("❌ aToken address est 0x0 - problème de configuration");
        }

        // 4. Mint des tokens de test
        console.log("💰 Mint de tokens de test...");
        const mintAmount = ethers.parseUnits("100000", 6); // 100k USDC
        await mockUSDC.mint(deployer.address, mintAmount);
        console.log(`✅ ${ethers.formatUnits(mintAmount, 6)} USDC mintés`);
        
    } else if (network.name === "sepolia") {
        console.log("\n🔧 Déploiement des mocks pour Sepolia...");
        
        // 1. Utiliser MockERC20 existant sur Sepolia
        USDC_ADDRESS = "0x5E2E77D678C0ABF06dD760C17D83F0aa53fDf35F";
        deployedContracts.MockUSDC = USDC_ADDRESS;
        console.log(`✅ MockUSDC utilisé à: ${USDC_ADDRESS}`);

        // 2. Deploy MockAavePool sur Sepolia
        console.log("🏦 Déploiement MockAavePool...");
        const mockAavePool = await ethers.deployContract("MockAavePool");
        await mockAavePool.waitForDeployment();
        AAVE_POOL_ADDRESS = mockAavePool.target.toString();
        deployedContracts.MockAavePool = AAVE_POOL_ADDRESS;
        console.log(`✅ MockAavePool déployé à: ${AAVE_POOL_ADDRESS}`);

        // 3. Configure aToken address AVANT de déployer ZentixVault
        console.log("⚙️ Configuration du aToken...");
        const tx = await mockAavePool.setATokenAddress(USDC_ADDRESS, USDC_ADDRESS);
        await tx.wait();
        console.log("✅ aToken configuré (MockUSDC = aUSDC pour simplifier)");
        
        // 3.1 Vérification de la configuration
        console.log("🔍 Vérification de la configuration aToken...");
        const reserveData = await mockAavePool.getReserveData(USDC_ADDRESS);
        console.log(`📋 aToken configuré dans reserve: ${reserveData.aTokenAddress}`);
        
        if (reserveData.aTokenAddress === "0x0000000000000000000000000000000000000000") {
            throw new Error("❌ aToken address est 0x0 - problème de configuration");
        }
        
        console.log("\n🌐 Configuration Sepolia avec mocks:");
        console.log(`   MockUSDC: ${USDC_ADDRESS}`);
        console.log(`   MockAave Pool: ${AAVE_POOL_ADDRESS}`);
    } else {
        throw new Error(`Réseau non supporté: ${network.name}`);
    }
    
    // 5. Deploy ZentixVault
    const constructorArgs = [USDC_ADDRESS, AAVE_POOL_ADDRESS];
    
    console.log("\n🏛️ Déploiement de ZentixVault...");
    const ZentixVault = await ethers.deployContract("ZentixVault", constructorArgs);
    await ZentixVault.waitForDeployment();
    
    const zentixVaultAddress = ZentixVault.target.toString();
    deployedContracts.ZentixVault = zentixVaultAddress;
    console.log(`✅ ZentixVault déployé à: ${zentixVaultAddress}`);
    
    // 6. Vérification de la configuration
    console.log("\n🔍 Vérification de la configuration...");
    try {
        const vaultUsdc = await ZentixVault.usdc();
        const vaultAavePool = await ZentixVault.aavePool();
        const aUSDCAddress = await ZentixVault.aUSDC();
        
        console.log(`✅ USDC configuré: ${vaultUsdc}`);
        console.log(`✅ Aave Pool configuré: ${vaultAavePool}`);
        console.log(`✅ aUSDC récupéré: ${aUSDCAddress}`);
        
    } catch (error) {
        console.error("❌ Erreur lors de la vérification:", error);
    }
    
    // 7. Vérification sur Etherscan (testnet seulement)
    if (!isLocalhost) {
        console.log("\n⏳ Attente avant vérification...");
        await ZentixVault.deploymentTransaction()?.wait(5);
        
        console.log("🔍 Vérification du contrat...");
        await verify(zentixVaultAddress, constructorArgs);
    }
    
    // 8. Résumé final
    console.log("\n📋 RÉSUMÉ DU DÉPLOIEMENT");
    console.log("========================");
    console.log(`Réseau: ${network.name}`);
    console.log(`ZentixVault: ${zentixVaultAddress}`);
    console.log(`MockUSDC: ${USDC_ADDRESS}`);
    console.log(`MockAavePool: ${AAVE_POOL_ADDRESS}`);
    
    // 9. Instructions pour le front-end
    console.log("\n🎯 POUR VOTRE FRONT-END:");
    console.log("========================");
    console.log(`✅ Adresse ZentixVault: ${zentixVaultAddress}`);
    console.log(`✅ Adresse MockUSDC: ${USDC_ADDRESS}`);
    console.log(`✅ Network: ${network.name}`);
    console.log(`✅ Chain ID: ${isLocalhost ? 31337 : 11155111}`);
}

main().catch((error) => {
    console.error("❌ Erreur de déploiement:", error);
    process.exitCode = 1;
});