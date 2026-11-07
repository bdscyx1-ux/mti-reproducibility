using System.Collections;
using System.Collections.Generic;
using UnityEngine;


namespace CY.DDMFinal.Units
{
    [CreateAssetMenu(fileName = "New Unit", menuName = "New Unit/Basic")]
    public class BasicUnit : ScriptableObject
    {
        public enum unitType
        {
            Farmer,
            Engineer,
            Soilder,
            Tank
        }

        public bool isPlayerUnit;
        public bool ableToFire;

        public unitType type;

        public string unitName;
        public GameObject playerPrefab;
        public GameObject enemyPrefab;

        public int productionCost;
        public int attackDamage;
        public int maxHealth;

        public float firingAccuracy;
        public float firingSpeed;
        public float firingRate;
        public float dodgeRate;
    }
}

