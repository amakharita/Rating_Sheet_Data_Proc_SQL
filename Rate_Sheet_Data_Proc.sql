
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:    <Adam Makharita>
-- Create date: <03/13/2016>
-- Description: <Rate Sheets from BUS - for London>
-- =============================================
CREATE PROCEDURE BUS_Rating_Data

@asof DATE 

AS 

SET @asof = 

/*Uncomment to run*/

DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)

BEGIN

IF OBJECT_ID('tempdb..#ratesheetyprl') IS NOT NULL
DROP TABLE #ratesheetyprl

/*TEMP*/

SELECT rl.policynumber 'Policy_Number', 
     MAX(pol_dtl.insured_name) 'Insured_Name',
     CAST(pol_dtl.effectivedate AS DATE) 'Effective_Date' , 
     CAST(pol_dtl.expirationdate AS DATE) 'Expiration_Date', 
     pol_dtl.Product,
     pol_dtl.Underwriter, 
     rl.sequence 'Location_Number',
     rl.PolicyRiskLocationId 'location_ID',
     Street + ' ' + COALESCE(Suite,'') as 'Street',
     City, 
     stateabbreviation 'State', 
     postalcode 'Postal_Code',
     countrycode 'Country_Code',
     rl.yearbuilt AS 'Year_Built',
     rl.numberofstories AS 'Number_of_Stories',
     CASE WHEN rl.occupancyclasstypeid = 1  THEN 'Single Family Home'
        WHEN rl.occupancyclasstypeid = 2  THEN 'Co-Op/Condo'
        WHEN rl.occupancyclasstypeid = 3  THEN 'Museum'
        WHEN rl.occupancyclasstypeid = 4  THEN 'Exhibition Space'
        WHEN rl.occupancyclasstypeid = 5  THEN 'Fine Arts Storage'
        WHEN rl.occupancyclasstypeid = 6  THEN 'Warehouse'
        WHEN rl.occupancyclasstypeid = 7  THEN 'Gallery'
        WHEN rl.occupancyclasstypeid = 8  THEN 'Office'
        WHEN rl.occupancyclasstypeid = 9  THEN 'Retail'
        WHEN rl.occupancyclasstypeid = 10 THEN 'Wholesale'
        WHEN rl.occupancyclasstypeid = 100 THEN OccupancyClassCustomDescription
     END AS 'Occupancy_Type',   
     CASE WHEN rl.Constructionclasstypeid = 1 THEN 'Frame'
        WHEN rl.Constructionclasstypeid = 2 THEN 'Joisted Masonry'
        WHEN rl.Constructionclasstypeid = 3 THEN 'Noncombustible'
        WHEN rl.Constructionclasstypeid = 4 THEN 'Masonry Noncombustible'
        WHEN rl.Constructionclasstypeid = 5 THEN 'Modified Fire Resistive'
        WHEN rl.Constructionclasstypeid = 6 THEN 'Fire Resistive'
        WHEN rl.constructionclasstypeid = 100 THEN constructionclasscustomDescription
     END AS 'Construction_Type',
     rl.Constructionclasstypeid AS 'Construction_Type_Code',
     'USD' AS Currency, 
     pol_dtl.policy_limit 'Policy_Limit',
     pol_bap_lmt.share_percent 'Part_of_Limit',
     pol_dtl.Excess,
     ded.deductible  'Policy_Deductible',
     prem.premium 'Gross_Policy_Premium',
     (prem.premium - addded.add_ded) 'Net_Policy_Premium',
     (SELECT CAST(MAX([XXX_PolicyAdministration].global.CustomProperty.PropertyValue) AS numeric)
      FROM XXX_policyadministration.PolicyAdministration.Policy
      INNER JOIN XXX_policyadministration.PolicyAdministration.PolicyRiskLocation 
      ON PolicyRiskLocation.PolicyId = Policy.PolicyId
      LEFT JOIN [XXX_PolicyAdministration].Global.CustomProperty 
      ON CustomProperty.InstanceId = PolicyRiskLocation.PolicyRiskLocationId
      LEFT JOIN [XXX_PolicyAdministration].Global.CustomPropertyDefinition 
      ON CustomProperty.CustomPropertyDefinitionId = CustomPropertyDefinition.CustomPropertyDefinitionId
      WHERE friendlyname = 'Value at Risk'
            AND PolicyRisklocation.PolicyRisklocationId = rl.policyrisklocationid
     ) Contents,
     (SELECT MAX([XXX_PolicyAdministration].global.CustomProperty.PropertyValue) AS CaliforniaEarthquakeLimitAmount
      FROM XXX_policyadministration.PolicyAdministration.Policy
      INNER JOIN XXX_policyadministration.PolicyAdministration.PolicyRiskLocation 
      ON PolicyRiskLocation.PolicyId = Policy.PolicyId
      LEFT JOIN [XXX_PolicyAdministration].Global.CustomProperty 
      ON CustomProperty.InstanceId = PolicyRiskLocation.PolicyRiskLocationId
      LEFT JOIN [XXX_PolicyAdministration].Global.CustomPropertyDefinition 
      ON CustomProperty.CustomPropertyDefinitionId = CustomPropertyDefinition.CustomPropertyDefinitionId
      WHERE friendlyname = 'Earthquake Limit (per location)'
            AND PolicyRisklocation.PolicyRisklocationId = rl.policyrisklocationid
      ) AS 'EQ_Limit',
      caeqded.amount AS 'EQ_Deductible',
      (SELECT MAX([XXX_PolicyAdministration].global.CustomProperty.PropertyValue) AS CaliforniaEarthquakeLimitAmount
       FROM XXX_policyadministration.PolicyAdministration.Policy
       INNER JOIN XXX_policyadministration.PolicyAdministration.PolicyRiskLocation 
       ON PolicyRiskLocation.PolicyId = Policy.PolicyId
       LEFT JOIN [XXX_PolicyAdministration].Global.CustomProperty 
       ON CustomProperty.InstanceId = PolicyRiskLocation.PolicyRiskLocationId
       LEFT JOIN [XXX_PolicyAdministration].Global.CustomPropertyDefinition
       ON CustomProperty.CustomPropertyDefinitionId = CustomPropertyDefinition.CustomPropertyDefinitionId
       WHERE friendlyname = 'Windstorm Limit (per location)'
             AND PolicyRisklocation.PolicyRisklocationId = rl.policyrisklocationid) AS 'WS_Limit',
     FLWSDED.amount AS 'WS_Deductible',
     PropertyValue 'Flood_Limit',
     floodded AS 'Flood_Deductible',
     CASE WHEN includeterror.IncludeTerror is null THEN 'N'
        ELSE includeterror.IncludeTerror
     END AS 'Include_Terror', 
     CASE WHEN tria.TRIAIncluded is null THEN 'N' 
       ELSE tria.TRIAIncluded 
     END AS 'Include_TRIA',
     CASE WHEN left(rl.policynumber,4)  in ('BFAJ', 'BFPC', 'BJBP', 'BAPS')
        THEN 'Y' 
        ELSE 'N' 
     END AS 'Personal_Terror'

INTO #ratesheetyprl
FROM  (SELECT p.policynumber, 
              prl.policyrisklocationid, 
        prl.sequence, 
        suite, 
        addr.Street, 
        addr.City, 
        addr.stateabbreviation, 
        addr.PostalCode, 
        yearbuilt, 
        numberofstories, 
        [Description], 
        Constructionclasstypeid, 
        constructionclasscustomDescription, 
        addr.countrycode, 
        OccupancyClassCustomDescription, 
        OccupancyClasstypeid
    FROM XXX_policyadministration.PolicyAdministratiON.Policy p
      LEFT JOIN XXX_policyadministration.[PolicyAdministratiON].[PolicyRisklocation] prl  
      ON p.policyid = prl.policyid
      LEFT JOIN XXX_policyadministration.[OrganizatiON].[Address] addr 
      ON addr.Parentid = prl.PolicyRisklocationId 
      LEFT JOIN XXX_policyadministration.PolicyAdministration.PolicyRisklocationbuilding prlb 
      ON prl.policyrisklocationid = prlb.policyrisklocationid 
    WHERE prl.RemovedFROMPolicyDate is null or prl.RemovedFROMPolicyDate > DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)
    GROUP BY  p.policynumber, 
          prl.policyrisklocationid, 
          prl.sequence, 
          suite, 
          addr.Street, 
          addr.City, 
          addr.stateabbreviation, 
          addr.PostalCode, 
          yearbuilt, 
          numberofstories, 
          [Description], 
          Constructionclasstypeid, 
          constructionclasscustomDescription, 
          addr.countrycode, 
          OccupancyClassCustomDescription, 
          OccupancyClasstypeid) rl 

  LEFT JOIN (SELECT pol_num, 
            SUM(amt) premium
        FROM XXX.dbo.fact_prem fp 
        WHERE fp.d_book  <= DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)
            AND data_source = 'bus'
            AND amt_type = 'premium'
        GROUP BY pol_num) prem ON prem.pol_num = rl.policynumber 

  LEFT JOIN (SELECT pol_num, 
            SUM(amt) add_ded
        FROM XXX.dbo.fact_prem fp 
        WHERE fp.d_book  <= DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)
            AND data_source = 'bus'
            AND amt_type = 'add_ded'
        GROUP BY pol_num) addded ON addded.pol_num = rl.policynumber 

  LEFT JOIN (SELECT PolicyRisklocation.PolicyRisklocationId, 
            policy.policynumber, 
            CAST(MAX(CustomProperty.PropertyValue) AS DEC) PropertyValue
        FROM XXX_policyadministration.PolicyAdministratiON.Policy
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyRisklocation 
          ON PolicyRisklocation.PolicyId = Policy.PolicyId
          INNER JOIN XXX_policyadministration.GLOBAL.CustomProperty 
          ON CustomProperty.InstanceId = PolicyRisklocation.PolicyRisklocationId
          INNER JOIN XXX_policyadministration.GLOBAL.CustomPropertyDefinitiON 
          ON CustomProperty.CustomPropertyDefinitiONId = CustomPropertyDefinitiON.CustomPropertyDefinitiONId
          INNER JOIN XXX.dbo.v_bus 
          ON v_bus.policynumber = policy.policynumber
          INNER JOIN (SELECT policy.[PolicyNumber],
                    Policy.PolicyId,
                    PolicyLimit.Amount
                FROM XXX_policyadministration.[PolicyAdministratiON].[Policy]
                  INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyCoveragePart 
                  ON Policy.PolicyId = PolicyCoveragePart.PolicyId
                  INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyLimit 
                  ON PolicyLimit.PolicyCoveragePartId = PolicyCoveragePart.PolicyCoveragePartId
                  INNER JOIN XXX_policyadministration.ProductDefinitiON.LimitDefinition 
                  ON PolicyLimit.LimitDefinitionId = LimitDefinition.LimitDefinitionId
                )  AS CaliforniaEarthquake ON CaliforniaEarthquake.PolicyId = Policy.PolicyId
                WHERE friendlyname = 'Flood Limit (per location)'
                    AND CustomProperty.PropertyValue is not null AND CustomProperty.PropertyValue <> '0'
                GROUP BY PolicyRisklocation.PolicyRisklocationId, policy.policynumber, CustomProperty.PropertyValue
        ) propertyvalue ON propertyvalue.policyrisklocationid = rl.policyrisklocationid

  LEFT JOIN (SELECT policynumber, 
            MAX(PolicyDeductibleSIR.amount) floodded
        FROM XXX_policyadministration.[PolicyAdministratiON].[Policy]
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyCoveragePart 
          ON Policy.PolicyId = PolicyCoveragePart.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyLimit 
          ON PolicyLimit.PolicyCoveragePartId = PolicyCoveragePart.PolicyCoveragePartId
          INNER JOIN XXX_policyadministration.ProductDefinitiON.LimitDefinition 
          ON PolicyLimit.LimitDefinitionId = LimitDefinition.LimitDefinitionId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyDeductibleSIR  
          ON PolicyDeductibleSIR.policycoveragepartid = PolicyCoveragePart.PolicyCoveragePartId
        WHERE PolicyDeductibleSIR.[Description] = 'Flood'
        GROUP BY policynumber) AS floodded 
  ON floodded.policynumber = rl.policynumber

  LEFT JOIN (SELECT policynumber, 
            MAX(PolicyDeductibleSIR.amount) deductible
        FROM XXX_policyadministration.[PolicyAdministratiON].[Policy]
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyCoveragePart 
          ON Policy.PolicyId = PolicyCoveragePart.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyLimit 
          ON PolicyLimit.PolicyCoveragePartId = PolicyCoveragePart.PolicyCoveragePartId
          INNER JOIN XXX_policyadministration.ProductDefinitiON.LimitDefinition 
          ON PolicyLimit.LimitDefinitionId = LimitDefinition.LimitDefinitionId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyDeductibleSIR  
          ON PolicyDeductibleSIR.policycoveragepartid = PolicyCoveragePart.PolicyCoveragePartId
        WHERE PolicyDeductibleSIR.[Description] = 'Policy Deductible'
        GROUP BY policynumber) ded ON ded.policynumber = rl.policynumber

  LEFT JOIN (SELECT policynumber, 
            MAX(PolicyDeductibleSIR.amount) amount
        FROM XXX_policyadministration.[PolicyAdministratiON].[Policy]
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyCoveragePart 
          ON Policy.PolicyId = PolicyCoveragePart.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyLimit 
          ON PolicyLimit.PolicyCoveragePartId = PolicyCoveragePart.PolicyCoveragePartId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyDeductibleSIR  
          ON PolicyDeductibleSIR.policycoveragepartid = PolicyCoveragePart.PolicyCoveragePartId
        WHERE PolicyDeductibleSIR.[Description] in ('Earthquake', 'california earthquake')
        GROUP BY policynumber) AS CAEQDED ON CAEQDED.policynumber = rl.policynumber

  LEFT JOIN (SELECT DISTINCT policynumber, 
            MAX(PolicyDeductibleSIR.amount) amount
        FROM XXX_policyadministration.[PolicyAdministratiON].[Policy]
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyCoveragePart 
          ON Policy.PolicyId = PolicyCoveragePart.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyLimit 
          ON PolicyLimit.PolicyCoveragePartId = PolicyCoveragePart.PolicyCoveragePartId
          INNER JOIN XXX_policyadministration.ProductDefinitiON.LimitDefinition 
          ON PolicyLimit.LimitDefinitionId = LimitDefinition.LimitDefinitionId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyDeductibleSIR  
          ON PolicyDeductibleSIR.policycoveragepartid = PolicyCoveragePart.PolicyCoveragePartId
        WHERE PolicyDeductibleSIR.[Description] in ('Windstorm', 'florida windstorm') 
        GROUP BY policynumber) AS FLWSDED ON FLWSDED.policynumber = rl.policynumber

  LEFT JOIN (SELECT DISTINCT policyrisklocationid, 
            CAST(SUM(PolicyLimit.Amount) AS DEC) 'Flood Limit'
        FROM XXX_policyadministration.[PolicyAdministratiON].[Policy]
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyRisklocation 
          ON PolicyRisklocation.PolicyId = Policy.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyCoveragePart 
          ON Policy.PolicyId = PolicyCoveragePart.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyLimit 
          ON PolicyLimit.PolicyCoveragePartId = PolicyCoveragePart.PolicyCoveragePartId
          INNER JOIN XXX_policyadministration.ProductDefinitiON.LimitDefinition 
          ON PolicyLimit.LimitDefinitionId = LimitDefinition.LimitDefinitionId
        WHERE LimitDefinition.Description in ('Flood')
        GROUP BY policyrisklocationid) AS FloodLimit ON FloodLimit.policyrisklocationid = rl.policyrisklocationid

  LEFT JOIN (SELECT policynumber, 
            CASE WHEN isnotcovered = '1'
              THEN 'N'
              ELSE 'Y' 
            END AS 'TRIAIncluded'
        FROM XXX_policyadministration.[PolicyAdministratiON].[Policy]
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyRisklocation 
          ON PolicyRisklocation.PolicyId = Policy.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyCoveragePart 
          ON Policy.PolicyId = PolicyCoveragePart.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyLimit 
          ON PolicyLimit.PolicyCoveragePartId = PolicyCoveragePart.PolicyCoveragePartId
          INNER JOIN XXX_policyadministration.ProductDefinitiON.LimitDefinition 
          ON PolicyLimit.LimitDefinitionId = LimitDefinition.LimitDefinitionId
        WHERE LimitDefinition.Description in ('TRIA')
        GROUP BY policynumber, 
            isnotcovered) AS tria ON tria.policynumber = rl.policynumber

  LEFT JOIN (SELECT policynumber, 
            CAST(PolicyLimit.Amount AS DEC) 
            policy_limit, MAX(name) 
            AS 'Insured_Name',
            policy.AttachmentPoint AS Excess,  
            EffectiveDate, 
            expirationDate, 
            div.Description AS 'Product', 
            COALESCE(ue.FirstName,'') + ' ' + COALESCE(ue.LastName,'') AS underwriter
        FROM XXX_policyadministration.[PolicyAdministratiON].[Policy]
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyRisklocation 
          ON PolicyRisklocation.PolicyId = Policy.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyCoveragePart 
          ON Policy.PolicyId = PolicyCoveragePart.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyLimit 
          ON PolicyLimit.PolicyCoveragePartId = PolicyCoveragePart.PolicyCoveragePartId
          INNER JOIN XXX_policyadministration.ProductDefinitiON.LimitDefinition 
          ON PolicyLimit.LimitDefinitionId = LimitDefinition.LimitDefinitionId
          LEFT JOIN XXX_PolicyAdministration.PolicyAdministration.PolicyInsured pins 
          ON policy.PolicyId = pins.PolicyId
          LEFT JOIN XXX_PolicyAdministration.PolicyAdministration.PolicyNamedInsured nins 
          ON pins.PolicyInsuredId = nins.PolicyInsuredId
          LEFT JOIN XXX_PolicyAdministration.Organization.Division div 
          ON policy.DivisionId = div.DivisionId
          LEFT JOIN XXX_PolicyAdministration.Organization.UnderwritingEmployee ue 
          ON policy.UnderwriterId = ue.UnderwritingEmployeeId
        WHERE LimitDefinition.Description in ('Policy Limit')
        GROUP BY policynumber, 
              CAST(PolicyLimit.Amount AS DEC), 
              name, 
              policy.AttachmentPoint, 
              EffectiveDate, 
              expirationDate, 
              div.Description, 
              COALESCE(ue.FirstName,'') + ' ' + COALESCE(ue.LastName,'')
        ) AS pol_dtl ON pol_dtl.policynumber = rl.policynumber

  LEFT JOIN (SELECT policynumber,
            CASE WHEN pol_bap_lmt.FullQuotaAmount IS NULL OR pol_bap_lmt.FullQuotaAmount = 0 
              THEN 0
              ELSE (pol_bap_lmt.Amount/pol_bap_lmt.FullQuotaAmount) * 100
            END AS share_percent
        FROM (SELECT pol.policynumber,
              pl.Amount AS Amount,
              pl.FullQuotaAmount AS FullQuotaAmount,
              pl.LimitDefinitionId
            FROM XXX_PolicyAdministration.PolicyAdministration.PolicyCoveragePart pcp
              LEFT JOIN XXX_PolicyAdministration.PolicyAdministration.PolicyLimit pl 
              ON pcp.PolicyCoveragePartId = pl.PolicyCoveragePartId
              LEFT JOIN XXX_PolicyAdministration.PolicyAdministration.Policy pol 
              ON pol.policyid = pcp.PolicyId
            WHERE pl.Description = 'Policy Limit'
          ) pol_bap_lmt
        GROUP BY policynumber,
          CASE WHEN pol_bap_lmt.FullQuotaAmount IS NULL OR pol_bap_lmt.FullQuotaAmount = 0 
              THEN 0
              ELSE (pol_bap_lmt.Amount/pol_bap_lmt.FullQuotaAmount) * 100
          END) AS pol_bap_lmt ON pol_bap_lmt.policynumber = rl.policynumber
  
  LEFT JOIN (SELECT policynumber, 
            CASE WHEN isnotcovered = '1'
              THEN 'N'
              ELSE 'Y' 
            END AS 'IncludeTerror'
        FROM XXX_policyadministration.[PolicyAdministratiON].[Policy]
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyRisklocation 
          ON PolicyRisklocation.PolicyId = Policy.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyCoveragePart 
          ON Policy.PolicyId = PolicyCoveragePart.PolicyId
          INNER JOIN XXX_policyadministration.PolicyAdministratiON.PolicyLimit 
          ON PolicyLimit.PolicyCoveragePartId = PolicyCoveragePart.PolicyCoveragePartId
          INNER JOIN XXX_policyadministration.ProductDefinitiON.LimitDefinition 
          ON PolicyLimit.LimitDefinitionId = LimitDefinition.LimitDefinitionId
        WHERE LimitDefinition.Description in ('Terrorism')
        GROUP BY policynumber, 
            isnotcovered) AS IncludeTerror ON [IncludeTerror].Policynumber = rl.policynumber
GROUP BY rl.policynumber, 
       CAST(pol_dtl.effectivedate AS DATE), 
       CAST(pol_dtl.expirationdate AS DATE), 
       pol_dtl.Product,
       pol_dtl.Underwriter, 
       rl.sequence,
       rl.PolicyRiskLocationId,
       Street + ' ' + COALESCE(Suite,''),
       City, 
       stateabbreviation, 
       postalcode,
       countrycode,
       rl.yearbuilt,
       rl.numberofstories,
       CASE WHEN rl.occupancyclasstypeid = 1  THEN 'Single Family Home'
          WHEN rl.occupancyclasstypeid = 2  THEN 'Co-Op/Condo'
          WHEN rl.occupancyclasstypeid = 3  THEN 'Museum'
          WHEN rl.occupancyclasstypeid = 4  THEN 'Exhibition Space'
          WHEN rl.occupancyclasstypeid = 5  THEN 'Fine Arts Storage'
          WHEN rl.occupancyclasstypeid = 6  THEN 'Warehouse'
          WHEN rl.occupancyclasstypeid = 7  THEN 'Gallery'
          WHEN rl.occupancyclasstypeid = 8  THEN 'Office'
          WHEN rl.occupancyclasstypeid = 9  THEN 'Retail'
          WHEN rl.occupancyclasstypeid = 10 THEN 'Wholesale'
          WHEN rl.occupancyclasstypeid = 100 THEN OccupancyClassCustomDescription
       END,   
       CASE WHEN rl.Constructionclasstypeid = 1 THEN 'Frame'
          WHEN rl.Constructionclasstypeid = 2 THEN 'Joisted Masonry'
          WHEN rl.Constructionclasstypeid = 3 THEN 'Noncombustible'
          WHEN rl.Constructionclasstypeid = 4 THEN 'Masonry Noncombustible'
          WHEN rl.Constructionclasstypeid = 5 THEN 'Modified Fire Resistive'
          WHEN rl.Constructionclasstypeid = 6 THEN 'Fire Resistive'
          WHEN rl.constructionclasstypeid = 100 THEN constructionclasscustomDescription
       END,
       rl.Constructionclasstypeid, 
       pol_dtl.policy_limit,
       pol_bap_lmt.share_percent,
       pol_dtl.Excess,
       ded.deductible,
       prem.premium,
       (prem.premium - addded.add_ded),
       caeqded.amount,
     FLWSDED.amount,
     PropertyValue,
     floodded,
     CASE WHEN includeterror.IncludeTerror is null THEN 'N'
        ELSE includeterror.IncludeTerror
     END, 
     CASE WHEN tria.TRIAIncluded is null THEN 'N' 
       ELSE tria.TRIAIncluded 
     END,
     CASE WHEN left(rl.policynumber,4)  in ('BFAJ', 'BFPC', 'BJBP', 'BAPS')
        THEN 'Y' 
        ELSE 'N' 
     END

SELECT [Policy_Number],
       [Insured_Name],
     [Effective_Date],
     [Expiration_Date],
     [Product],
     [Underwriter],
     [Location_Number],
     [location_ID],
     [Street],
     [City],
     [State],
     [Postal_Code],
     [Country_Code],
     [Year_Built],
     [Number_of_Stories],
     CAST([Occupancy_Type] as varchar(30)) [Occupancy_Type],
     [Construction_Type],
     [Construction_Type_Code],
     [Currency],
     [Policy_Limit], 
     [Part_of_Limit],
     [Excess],
     CAST([Policy_Deductible]as dec) [Policy_Deductible],
     [Gross_Policy_Premium],
     [Net_Policy_Premium],
     CASE WHEN product = 'jewelers block' AND (contents = 0 or contents is null)
      THEN [Policy_Limit]
      ELSE Contents
     END AS 
     [Contents],
     CAST(MAX([EQ_Limit]) AS DEC) [EQ_Limit],
     CAST(MAX([EQ_Deductible])AS DEC) [EQ_Deductible],
     CAST([WS_Limit]AS DEC) [WS_Limit],
     CAST([WS_Deductible]AS DEC) [WS Deductible],
     CAST(MAX([Flood_Limit]) AS DEC) [Flood_Limit],
     CAST([Flood_Deductible] AS DEC) [Flood_Deductible],
     [Include_Terror],
     [Include_TRIA],
     [Personal_Terror]

FROM #RateSheetYPRL
WHERE @asof BETWEEN [Effective_Date] AND [Expiration_Date]
      AND product <> 'specie'
GROUP BY [Policy_Number],
         [Insured_Name],
       [Effective_Date],
       [Expiration_Date],
       [Product],
       [Underwriter],
       [Location_Number],
       [location_ID],
       [Street],
       [City],
       [State],
       [Postal_Code],
       [Country_Code],
       [Year_Built],
       [Number_of_Stories],
       CAST([Occupancy_Type] as varchar(30)),
       [Construction_Type],
       [Construction_Type_Code],
       [Currency],
       [Policy_Limit], 
       [Part_of_Limit],
       [Excess],
       CAST([Policy_Deductible]as dec),
       [Gross_Policy_Premium],
       [Net_Policy_Premium],
       CASE WHEN product = 'jewelers block' AND (contents = 0 or contents is null)
        THEN [Policy_Limit]
        ELSE Contents
       END,
       CAST([WS_Limit]AS DEC),
       CAST([WS_Deductible]AS DEC),
       CAST([Flood_Deductible] AS DEC),
       [Include_Terror],
       [Include_TRIA],
       [Personal_Terror]
ORDER BY 1, 7, 8




END
GO
