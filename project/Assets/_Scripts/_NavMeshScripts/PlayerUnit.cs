using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.AI;

namespace CY.DDMFinal.Player
{
    [RequireComponent(typeof(NavMeshAgent))]
    public class PlayerUnit : MonoBehaviour
    {
        private NavMeshAgent navAgent;

        private void OnEnable()
        {
            navAgent = GetComponent<NavMeshAgent>();
            navAgent.speed = 20.0f;
        }

        public void MoveUnits(Vector3 _destinationPoint)
        {
            navAgent.SetDestination(_destinationPoint);
        }
    }
}

