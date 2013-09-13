{-# LANGUAGE DataKinds #-}

module HLearn.DataStructures.SpaceTree.Algorithms.NearestNeighbor
    where

import qualified Data.Map as Map
import GHC.TypeLits
import HLearn.Algebra
import HLearn.DataStructures.SpaceTree

-------------------------------------------------------------------------------
-- data types 

data Neighbor dp = Neighbor
    { neighbor         :: !dp
    , neighborDistance :: !(Ring dp)
    }

deriving instance (Read dp, Read (Ring dp)) => Read (Neighbor dp)
deriving instance (Show dp, Show (Ring dp)) => Show (Neighbor dp)

instance Eq (Ring dp) => Eq (Neighbor dp) where
    a == b = neighborDistance a == neighborDistance b

instance Ord (Ring dp) => Ord (Neighbor dp) where
    compare a b = compare (neighborDistance a) (neighborDistance b)

---------------------------------------

newtype KNN (k::Nat) dp = KNN { getknn :: [Neighbor dp] }

deriving instance (Read dp, Read (Ring dp)) => Read (KNN k dp)
deriving instance (Show dp, Show (Ring dp)) => Show (KNN k dp)

---------------------------------------

newtype KNN2 (k::Nat) dp = KNN2 { getknn2 :: Map.Map dp (KNN k dp) }

deriving instance (Read dp, Read (Ring dp), Ord dp, Read (KNN k dp)) => Read (KNN2 k dp)
deriving instance (Show dp, Show (Ring dp), Ord dp, Show (KNN k dp)) => Show (KNN2 k dp)

-------------------------------------------------------------------------------
-- algebra

instance (SingI k, MetricSpace dp, Eq dp) => Monoid (KNN k dp) where
    mempty = KNN []
    mappend (KNN xs) (KNN ys) = KNN $ take k $ interleave xs ys
        where
            k=fromIntegral $ fromSing (sing :: Sing k)

instance (SingI k, MetricSpace dp, Ord dp) => Monoid (KNN2 k dp) where
    mempty = KNN2 mempty
    mappend (KNN2 x) (KNN2 y) = KNN2 $ Map.unionWith (<>) x y

-------------------------------------------------------------------------------
-- dual tree

knn2_slow :: (SpaceTree t dp, Ord dp, SingI k) => DualTree (t dp) -> KNN2 k dp
knn2_slow = prunefold2init initKNN2 noprune (knn2_cata)

initKNN2 :: SpaceTree t dp => DualTree (t dp) -> KNN2 k dp
initKNN2 dual = KNN2 $ Map.singleton qnode val
    where
        rnode = stNode $ reference dual
        qnode = stNode $ query dual
        val = KNN [Neighbor rnode (distance qnode rnode)]

knn2_prune :: SpaceTree t dp => KNN2 k dp -> DualTree (t dp) -> Bool
knn2_prune = undefined

knn2_cata :: (SingI k, Ord dp, MetricSpace dp) => DualTree dp -> KNN2 k dp -> KNN2 k dp 
knn2_cata dual knn2 = KNN2 $ Map.insertWith (<>) qnode knn' $ getknn2 knn2
    where
        rnode = reference dual 
        qnode = query dual 
        dualdist = distance rnode qnode
        knn' = KNN [ Neighbor rnode dualdist ]


-- prunefold2init :: SpaceTree t dp =>
--     (DualTree (t dp) -> res) -> 
--         (res -> DualTree (t dp) -> Bool) -> (DualTree dp -> res -> res) -> DualTree (t dp) -> res
-- prunefold2init init prune f pair = foldl' 
--     (prunefold2 prune f) 
--     (init pair) 
--     (dualTreeMatrix (stChildren $ reference pair) (stChildren $ query pair))

-------------------------------------------------------------------------------
-- single tree

init_neighbor :: SpaceTree t dp => dp -> t dp -> Neighbor dp
init_neighbor query t = Neighbor
    { neighbor = stNode t
    , neighborDistance = distance query (stNode t)
    }

nearestNeighbor :: SpaceTree t dp => dp -> t dp -> Neighbor dp
nearestNeighbor query t = prunefoldinit (init_neighbor query) (nn_prune query) (nn_cata query) t

nearestNeighbor_slow :: SpaceTree t dp => dp -> t dp -> Neighbor dp
nearestNeighbor_slow query t = prunefoldinit undefined noprune (nn_cata query) t

nn_prune :: SpaceTree t dp => dp -> Neighbor dp -> t dp -> Bool
nn_prune query b t = neighborDistance b < distance query (stNode t)

nn_cata :: MetricSpace dp => dp -> dp -> Neighbor dp -> Neighbor dp
nn_cata query next current = if neighborDistance current < nextDistance
    then current
    else Neighbor next nextDistance
    where
        nextDistance = distance query next

---------------------------------------

knn :: (SingI k, SpaceTree t dp, Eq dp) => dp -> t dp -> KNN k dp
knn query t = prunefoldinit (init_knn query) (knn_prune query) (knn_cata query) t

knn_prune :: forall k t dp. (SingI k, SpaceTree t dp) => dp -> KNN k dp -> t dp -> Bool
knn_prune query res t = knnMaxDistance res < distance query (stNode t) && knnFull res

knn_cata :: (SingI k, MetricSpace dp, Eq dp) => dp -> dp -> KNN k dp -> KNN k dp
knn_cata query next current = KNN [Neighbor next $ distance query next] <> current

knnFull :: forall k dp. SingI k => KNN k dp -> Bool
knnFull knn = length (getknn knn) > k
    where
        k = fromIntegral $ fromSing (sing :: Sing k)

knnMaxDistance :: KNN k dp -> Ring dp
knnMaxDistance (KNN xs) = neighborDistance $ last xs

init_knn :: SpaceTree t dp => dp -> t dp -> KNN k dp
init_knn query t = KNN [Neighbor (stNode t) (distance (stNode t) query)]

-- interleave :: Ord a => [a] -> [a] -> [a]
interleave xs [] = xs
interleave [] ys = ys
interleave (x:xs) (y:ys) = case compare x y of
    LT -> x:(interleave xs (y:ys))
    GT -> y:(interleave (x:xs) ys)
    EQ -> if neighbor x == neighbor y
        then x:interleave xs ys
        else x:y:interleave xs ys
