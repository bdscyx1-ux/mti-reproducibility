using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace CY.DDMFinal.Units
{
    public class UnitHandler : MonoBehaviour
    {
        public BasicUnit _unit;

        public Transform farmers;
        // Start is called before the first frame update
        void Start()
        {
            GameObject unit = Instantiate(_unit.playerPrefab, transform.position, Quaternion.identity);
        }
    }

}
